import Foundation
import Observation

@Observable
final class BatchImportViewModel {
    static let linkLimit = 10
    private static let concurrentChecks = 3

    enum Phase: Equatable {
        case editing, reviewing, checking, saving
    }

    struct Failure: Equatable, Sendable {
        let message: String
        let canRetry: Bool

        init(_ error: any Error) {
            message = FeatureError.message(for: error)
            canRetry = FeatureError.isRetryable(error)
        }
    }

    struct Draft: Equatable, Sendable {
        let id = UUID()
        let metadata: ImportedVideoMetadata

        func makeVideo() -> VideoItem { metadata.makeVideo(id: id) }
    }

    struct Row: Identifiable, Equatable, Sendable {
        enum Status: Equatable, Sendable {
            case waiting, checking, repeatedLink
            case checkFailed(Failure)
            case ready(Draft), saving(Draft), saved(VideoItem), alreadySaved(VideoItem)
            case saveFailed(Draft, Failure)

            var video: VideoItem? {
                switch self {
                case let .ready(draft), let .saving(draft), let .saveFailed(draft, _): draft.makeVideo()
                case let .saved(video), let .alreadySaved(video): video
                default: nil
                }
            }

            var canCheck: Bool {
                switch self {
                case .waiting: true
                case let .checkFailed(failure): failure.canRetry
                default: false
                }
            }

            var draftToSave: Draft? {
                switch self {
                case let .ready(draft): draft
                case let .saveFailed(draft, failure) where failure.canRetry: draft
                default: nil
                }
            }
        }

        let id: Int
        let source: String
        var status: Status
    }

    private struct Check: Sendable {
        let index: Int
        let url: URL
    }

    private struct CheckResult: Sendable {
        let index: Int
        let status: Row.Status
    }

    private let pipeline: any VideoImportPipeline
    private let videoRepository: any VideoItemRepository

    var input = ""
    private(set) var phase: Phase = .editing
    private(set) var rows: [Row] = []

    // Keep the identity of prepared and submitted videos even if their lines are edited out and re-added.
    private var previousResults: [URL: Row.Status] = [:]

    var linkCount: Int { inputLines.count }
    var checkableCount: Int { rows.count(where: { $0.status.canCheck }) }
    var saveableCount: Int { rows.count(where: { $0.status.draftToSave != nil }) }
    var checkedCount: Int {
        rows.count(where: { $0.status != .waiting && $0.status != .checking })
    }
    var savedCount: Int {
        rows.count(where: { if case .saved = $0.status { true } else { false } })
    }

    var hasPendingWork: Bool {
        checkableCount > 0 || saveableCount > 0 || phase == .checking
    }

    var canReviewInput: Bool { (1...Self.linkLimit).contains(linkCount) }

    private var inputLines: [String] {
        input.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    init(pipeline: any VideoImportPipeline, videoRepository: any VideoItemRepository) {
        self.pipeline = pipeline
        self.videoRepository = videoRepository
    }

    func editLinks() {
        guard phase == .reviewing else { return }
        phase = .editing
    }

    func reviewInput() async {
        guard phase == .editing, canReviewInput else { return }
        var seen = Set<URL>()
        rows = inputLines.enumerated().map { index, source in
            let status: Row.Status
            if let url = Self.parseLink(source) {
                let key = Self.linkKey(url)
                status = seen.insert(key).inserted ? previousResults[key] ?? .waiting : .repeatedLink
            } else {
                status = .checkFailed(Failure(VideoImportError.invalidURL))
            }
            return Row(id: index, source: source, status: status)
        }
        phase = .reviewing
        await checkRemaining()
    }

    func checkRemaining() async {
        guard phase == .reviewing else { return }
        let checks = rows.compactMap { row -> Check? in
            guard row.status.canCheck, let url = Self.parseLink(row.source) else { return nil }
            return Check(index: row.id, url: url)
        }
        guard !checks.isEmpty else { return }
        phase = .checking
        defer {
            for check in checks where rows[check.index].status == .checking {
                rows[check.index].status = .waiting
            }
            phase = .reviewing
        }

        await withTaskGroup(of: CheckResult?.self) { group in
            var queued = checks.makeIterator()

            @MainActor func scheduleNext() {
                guard let check = queued.next(), group.addTaskUnlessCancelled(operation: {
                    await self.checkLink(check)
                }) else { return }
                rows[check.index].status = .checking
            }

            for _ in 0..<Self.concurrentChecks { scheduleNext() }
            while let result = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if let result { updateStatus(result.status, at: result.index) }
                scheduleNext()
            }
        }
    }

    @discardableResult
    func saveReady() async -> Bool {
        guard phase == .reviewing, saveableCount > 0 else { return false }
        phase = .saving
        defer { phase = .reviewing }

        var shouldRefreshLibrary = false
        for index in rows.indices {
            guard !Task.isCancelled else { break }
            guard let draft = rows[index].status.draftToSave else { continue }
            let isRetry: Bool = if case .saveFailed = rows[index].status { true } else { false }
            let video = draft.makeVideo()
            updateStatus(.saving(draft), at: index)
            do {
                try await videoRepository.saveVideo(video)
                updateStatus(.saved(video), at: index)
                shouldRefreshLibrary = true
            } catch where FeatureError.code(for: error) == "duplicate_video" {
                // A retry may find the UUID from a save whose response was lost.
                if isRetry, let existing = try? await videoRepository.videos().first(where: { $0.id == video.id }) {
                    updateStatus(.saved(existing), at: index)
                } else {
                    updateStatus(.alreadySaved(video), at: index)
                }
                shouldRefreshLibrary = true
            } catch {
                let failure = error is CancellationError
                    ? Failure(APIClientError.networkUnavailable) : Failure(error)
                updateStatus(.saveFailed(draft, failure), at: index)
                if Task.isCancelled || APIClientError.isOffline(error) || error is OfflineError { break }
            }
        }
        return shouldRefreshLibrary
    }

    private func checkLink(_ check: Check) async -> CheckResult? {
        do {
            try Task.checkCancellation()
            let platform = try await pipeline.detectPlatform(from: check.url)
            try Task.checkCancellation()
            let metadata = try await pipeline.extractMetadata(from: check.url, platform: platform)
            try Task.checkCancellation()
            return CheckResult(index: check.index, status: .ready(Draft(metadata: metadata)))
        } catch is CancellationError {
            return nil
        } catch {
            return CheckResult(index: check.index, status: .checkFailed(Failure(error)))
        }
    }

    private func updateStatus(_ status: Row.Status, at index: Int) {
        rows[index].status = status
        if let url = Self.parseLink(rows[index].source) {
            previousResults[Self.linkKey(url)] = status
        }
    }

    private static func parseLink(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace),
              let url = URL(string: text, encodingInvalidCharacters: false),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    // Match share links within the batch without rewriting the URL sent to the API.
    private static func linkKey(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        if let query = parts.percentEncodedQueryItems {
            let kept = query.filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !["si", "igsh", "_t", "_r"].contains(name)
            }
            if kept.count != query.count { parts.percentEncodedQueryItems = kept.isEmpty ? nil : kept }
        }
        return parts.url ?? url
    }
}
