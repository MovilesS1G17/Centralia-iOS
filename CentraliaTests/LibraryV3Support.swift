import Foundation
@testable import Centralia

/// An error shaped like the V3 API body: a stable `code` and a user-facing `detail`.
struct V3APIError: LocalizedError, CodedError, Equatable {
    let code: String
    let detail: String

    var errorDescription: String? { detail }

    static let videoNotFound = V3APIError(
        code: "video_not_found",
        detail: "This short is no longer in your library."
    )
}

extension ClientAnalyticsEvent {
    /// Properties as plain strings, so tests can compare them directly.
    var flatProperties: [String: String] {
        properties.mapValues { value in
            switch value {
            case let .text(text): text
            case let .integer(number): String(number)
            case let .decimal(number): String(number)
            case let .boolean(flag): String(flag)
            }
        }
    }
}

/// Records every event so tests can assert what the screens emit.
final class RecordingAnalyticsTracking: AnalyticsTracking, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ClientAnalyticsEvent] = []

    nonisolated init() {}

    var events: [ClientAnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func track(_ event: ClientAnalyticsEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }

    func events(named name: String) -> [ClientAnalyticsEvent] {
        events.filter { $0.name == name }
    }
}

/// An in-memory library that can be told to fail with the errors the V3
/// backend returns: `duplicate_video`, `folder_name_duplicate`,
/// `video_not_found`, `unsupported_source` and `folder_not_found`.
@MainActor
final class V3SimulatedLibrary: VideoItemRepository, FolderRepository, VideoImportPipeline {
    var storedVideos: [VideoItem]
    var storedFolders: [LibraryFolder]
    var listError: Error?
    var saveError: Error?
    var mutationError: Error?
    var folderError: Error?
    var importError: Error?
    var tagsError: Error?
    var suggestionError: Error?
    var suggestedTags: [String] = []
    var suggestedFolderName: String?
    var importedMetadata = ImportedVideoMetadata(
        sourceURL: URL(string: "https://www.tiktok.com/@maker/video/1")!,
        platform: .tiktok,
        creator: "@maker",
        durationSeconds: 30,
        sourceCaption: "Caption",
        transcript: nil,
        extractedOnScreenText: nil,
        generatedSummary: "Summary"
    )

    init(videos: [VideoItem] = [], folders: [LibraryFolder] = []) {
        storedVideos = videos
        storedFolders = folders
    }

    // MARK: VideoItemRepository

    func videos() async throws -> [VideoItem] {
        if let listError { throw listError }
        return storedVideos
    }

    func saveVideo(_ video: VideoItem) async throws {
        if let saveError { throw saveError }
        if storedVideos.contains(where: { $0.sourceURL == video.sourceURL }) {
            throw VideoItemRepositoryError.duplicateVideo
        }
        if let folderID = video.folderID, !storedFolders.contains(where: { $0.id == folderID }) {
            throw FolderRepositoryError.folderNotFound
        }
        storedVideos.append(video)
    }

    func deleteVideo(id: UUID) async throws {
        if let mutationError { throw mutationError }
        guard storedVideos.contains(where: { $0.id == id }) else { throw V3APIError.videoNotFound }
        storedVideos.removeAll { $0.id == id }
    }

    func restoreVideo(_ video: VideoItem) async throws {
        if let mutationError { throw mutationError }
        storedVideos.append(video)
    }

    func moveVideo(id: UUID, to folderID: UUID?) async throws {
        if let mutationError { throw mutationError }
        guard let index = storedVideos.firstIndex(where: { $0.id == id }) else {
            throw V3APIError.videoNotFound
        }
        if let folderID, !storedFolders.contains(where: { $0.id == folderID }) {
            throw FolderRepositoryError.folderNotFound
        }
        storedVideos[index].folderID = folderID
    }

    func updateNote(id: UUID, note: String?) async throws {
        if let mutationError { throw mutationError }
        guard let index = storedVideos.firstIndex(where: { $0.id == id }) else {
            throw V3APIError.videoNotFound
        }
        storedVideos[index].note = note
    }

    func updateTags(id: UUID, tags: [String]) async throws {
        if let mutationError { throw mutationError }
        guard let index = storedVideos.firstIndex(where: { $0.id == id }) else {
            throw V3APIError.videoNotFound
        }
        storedVideos[index].tags = TagCatalog.normalize(tags)
    }

    // MARK: FolderRepository

    func folders() async throws -> [LibraryFolder] {
        if let listError { throw listError }
        return storedFolders
    }

    func createFolder(named name: String, symbolName: String) async throws -> LibraryFolder {
        if let folderError { throw folderError }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FolderRepositoryError.emptyName }
        guard !storedFolders.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            throw FolderRepositoryError.duplicateName
        }
        let folder = LibraryFolder(id: UUID(), name: trimmed, symbolName: symbolName)
        storedFolders.append(folder)
        return folder
    }

    func renameFolder(id: UUID, to name: String) async throws -> LibraryFolder {
        if let folderError { throw folderError }
        guard let index = storedFolders.firstIndex(where: { $0.id == id }) else {
            throw FolderRepositoryError.folderNotFound
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FolderRepositoryError.emptyName }
        guard !storedFolders.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) else {
            throw FolderRepositoryError.duplicateName
        }
        storedFolders[index].name = trimmed
        return storedFolders[index]
    }

    func deleteFolder(id: UUID) async throws {
        if let folderError { throw folderError }
        guard storedFolders.contains(where: { $0.id == id }) else {
            throw FolderRepositoryError.folderNotFound
        }
        storedFolders.removeAll { $0.id == id }
        for index in storedVideos.indices where storedVideos[index].folderID == id {
            storedVideos[index].folderID = nil
        }
    }

    // MARK: VideoImportPipeline

    func detectPlatform(from sourceURL: URL) async throws -> VideoPlatform {
        if let importError { throw importError }
        return importedMetadata.platform
    }

    func extractMetadata(from sourceURL: URL, platform: VideoPlatform) async throws -> ImportedVideoMetadata {
        if let importError { throw importError }
        return importedMetadata
    }

    func generateTags(for metadata: ImportedVideoMetadata) async throws -> [String] {
        if let tagsError { throw tagsError }
        return suggestedTags
    }

    func suggestFolder(for metadata: ImportedVideoMetadata, tags: [String]) async throws -> String? {
        if let suggestionError { throw suggestionError }
        return suggestedFolderName
    }
}

/// Playback with a scripted answer, as `GET /v1/videos/{id}/playback` would give.
@MainActor
final class ScriptedPlaybackRepository: VideoPlaybackRepository {
    var result: Result<VideoPlayback, Error>
    private(set) var requestedIDs: [UUID] = []

    init(_ result: Result<VideoPlayback, Error>) {
        self.result = result
    }

    func playback(for videoID: UUID) async throws -> VideoPlayback {
        requestedIDs.append(videoID)
        return try result.get()
    }
}

/// An analytics endpoint that records batches and can be told to fail.
@MainActor
final class RecordingAnalyticsRepository: AnalyticsRepository {
    private(set) var batches: [[ClientAnalyticsEvent]] = []
    var error: Error?

    func record(_ events: [ClientAnalyticsEvent]) async throws {
        if let error { throw error }
        batches.append(events)
    }
}

/// An analytics endpoint that holds every call until released, so a send
/// can be kept in flight while more events arrive.
@MainActor
final class GatedAnalyticsRepository: AnalyticsRepository {
    private(set) var batches: [[ClientAnalyticsEvent]] = []
    private(set) var callsStarted = 0
    var isBlocking = true

    func record(_ events: [ClientAnalyticsEvent]) async throws {
        callsStarted += 1
        while isBlocking {
            try await Task.sleep(for: .milliseconds(5))
        }
        batches.append(events)
    }
}

extension V3APIError {
    static func server(_ code: String, _ detail: String) -> APIClientError {
        .server(status: 422, code: code, detail: detail, email: nil, retryAfter: nil)
    }
}

enum LibraryFixtures {
    static func video(
        id: UUID = UUID(),
        url: String = "https://www.tiktok.com/@maker/video/1",
        platform: VideoPlatform = .tiktok,
        creator: String = "@maker",
        caption: String? = nil,
        transcript: String? = nil,
        customTitle: String? = nil,
        folderID: UUID? = nil,
        tags: [String] = [],
        savedAt: Date = Date()
    ) -> VideoItem {
        VideoItem(
            id: id,
            sourceURL: URL(string: url)!,
            platform: platform,
            creator: creator,
            durationSeconds: 30,
            sourceCaption: caption,
            transcript: transcript,
            extractedOnScreenText: nil,
            generatedSummary: nil,
            customTitle: customTitle,
            folderID: folderID,
            tags: tags,
            note: nil,
            savedAt: savedAt,
            analysisStatus: .completed
        )
    }
}
