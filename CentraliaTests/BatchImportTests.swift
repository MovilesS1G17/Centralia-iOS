import Foundation
import Testing
@testable import Centralia

@MainActor
struct BatchImportTests {
    @Test func limitsConcurrentChecksAndPublishesEachResultInPlace() async throws {
        let pipeline = ControlledBatchPipeline()
        let model = BatchImportViewModel(pipeline: pipeline, videoRepository: V3SimulatedLibrary())
        let sources = (1...4).map(link) + [link(1) + "?si=share", "invalid"]
        model.input = sources.joined(separator: "\n")

        let task = Task { await model.reviewInput() }
        defer { task.cancel() }
        try await waitUntil { pipeline.active.count == 3 }
        #expect(pipeline.active == Set(["short1", "short2", "short3"]))

        pipeline.finish("short3")
        try await waitUntil { pipeline.active.contains("short4") }
        #expect(model.rows.map(\.source) == sources)
        #expect(model.rows[0].status == .checking)
        #expect(model.rows[2].status.draftToSave != nil)
        #expect(model.rows[4].status == .repeatedLink)
        #expect(model.rows[5].status == .checkFailed(.init(VideoImportError.invalidURL)))

        pipeline.finishAll()
        await task.value
        #expect(pipeline.peak == 3)
        #expect(model.saveableCount == 4)
    }

    @Test func stoppingAnalysisKeepsFinishedRowsAndResumesTheRest() async throws {
        let pipeline = ControlledBatchPipeline()
        let model = BatchImportViewModel(pipeline: pipeline, videoRepository: V3SimulatedLibrary())
        model.input = [link(1), link(2), link(3)].joined(separator: "\n")

        let check = Task { await model.reviewInput() }
        defer { check.cancel() }
        try await waitUntil { pipeline.active.count == 3 }
        pipeline.finish("short2")
        try await waitUntil { model.saveableCount == 1 }
        check.cancel()
        await check.value

        #expect(model.phase == .reviewing)
        #expect(model.rows[0].status == .waiting)
        #expect(model.rows[2].status == .waiting)
        let finished = try #require(model.rows[1].status.draftToSave)

        let retry = Task { await model.checkRemaining() }
        defer { retry.cancel() }
        try await waitUntil { pipeline.active.count == 2 }
        pipeline.finishAll()
        await retry.value
        #expect(model.savedCount == 0)
        #expect(model.saveableCount == 3)
        #expect(model.rows[1].status.draftToSave == finished)
    }

    @Test func retriesAnInterruptedSaveWithTheSameIDAndSkipsAnExistingShort() async throws {
        let library = V3SimulatedLibrary(videos: [LibraryFixtures.video(url: link(3))])
        let model = BatchImportViewModel(pipeline: MockVideoImportPipeline(delay: .zero), videoRepository: library)
        model.input = [link(1), link(2), link(3)].joined(separator: "\n")
        await model.reviewInput()

        library.saveError = APIClientError.networkUnavailable
        #expect(!(await model.saveReady()))
        guard case let .saveFailed(draft, failure) = model.rows[0].status else {
            Issue.record("The first save should have entered a retryable failure state")
            return
        }
        #expect(failure.canRetry)
        #expect(model.rows[1].status.draftToSave != nil)

        // The backend had committed the row before the client lost the response.
        let committed = draft.makeVideo()
        library.storedVideos.append(committed)
        library.saveError = nil

        #expect(await model.saveReady())
        #expect(model.rows[0].status == .saved(committed))
        #expect(model.savedCount == 2)
        #expect(model.saveableCount == 0)
        guard case .alreadySaved = model.rows[2].status else {
            Issue.record("The existing short should be marked as already saved")
            return
        }
        #expect(library.storedVideos.count == 3)
        #expect(library.storedVideos.suffix(2).allSatisfy { $0.folderID == nil })
    }

    private func link(_ index: Int) -> String { "https://www.youtube.com/shorts/short\(index)" }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while !condition() && clock.now < deadline {
            try await clock.sleep(for: .milliseconds(5))
        }
        try #require(condition())
    }
}

@MainActor
private final class ControlledBatchPipeline: VideoImportPipeline {
    private let demo = MockVideoImportPipeline(delay: .zero)
    private var gates: [String: AsyncStream<Void>.Continuation] = [:]
    private(set) var peak = 0
    var active: Set<String> { Set(gates.keys) }

    func detectPlatform(from sourceURL: URL) async throws -> VideoPlatform {
        try await demo.detectPlatform(from: sourceURL)
    }

    func extractMetadata(from sourceURL: URL, platform: VideoPlatform) async throws -> ImportedVideoMetadata {
        let id = sourceURL.lastPathComponent
        let (stream, gate) = AsyncStream<Void>.makeStream()
        gates[id] = gate
        peak = max(peak, gates.count)
        defer { gates.removeValue(forKey: id) }
        for await _ in stream {}
        try Task.checkCancellation()
        return try await demo.extractMetadata(from: sourceURL, platform: platform)
    }

    func finish(_ id: String) { gates[id]?.finish() }
    func finishAll() { gates.values.forEach { $0.finish() } }

    func generateTags(for metadata: ImportedVideoMetadata) async throws -> [String] { [] }
    func suggestFolder(for metadata: ImportedVideoMetadata, tags: [String]) async throws -> String? { nil }
}
