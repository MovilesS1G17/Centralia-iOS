import Foundation
import Testing
@testable import Centralia

@MainActor
struct FolderSuggestionCacheTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let account = UUID()
    private let folder = LibraryFolder(id: UUID(), name: "Design", symbolName: "paintpalette")

    @Test func persistedHitsExpireAndRequireTheSameInputsAndFolderInventory() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initial = makeCache(directory)
        let video = LibraryFixtures.video(tags: ["design"])
        let first = await initial.lookup(for: account, videos: [video], folders: [folder])
        await initial.save([.init(videoID: video.id, folderID: folder.id)], from: first)

        let reopened = makeCache(directory)
        #expect(await reopened.lookup(for: account, videos: [video], folders: [folder]).folderIDs == [video.id: folder.id])
        #expect(await reopened.lookup(for: UUID(), videos: [video], folders: [folder]).folderIDs.isEmpty)
        var renamed = folder
        renamed.name = "Workshop"
        #expect(await reopened.lookup(for: account, videos: [video], folders: [renamed]).folderIDs.isEmpty)
        #expect(await reopened.lookup(for: account, videos: [video], folders: []).folderIDs.isEmpty)
        let another = LibraryFolder(id: UUID(), name: "Craft", symbolName: "folder")
        #expect(await reopened.lookup(for: account, videos: [video], folders: [folder, another]).folderIDs.isEmpty)

        var edited = video
        edited.tags = ["studio"]
        #expect(await reopened.lookup(for: account, videos: [edited], folders: [folder]).folderIDs.isEmpty)
        let differentCaption = LibraryFixtures.video(id: video.id, caption: "Changed caption", tags: ["design"])
        #expect(await reopened.lookup(for: account, videos: [differentCaption], folders: [folder]).folderIDs.isEmpty)
        edited = video
        edited.note = "A personal note"
        let newIcon = LibraryFolder(id: folder.id, name: folder.name, symbolName: "pencil")
        #expect(await reopened.lookup(for: account, videos: [edited], folders: [newIcon]).folderIDs == [video.id: folder.id])

        let almostExpired = makeCache(directory, offset: 86_399)
        #expect(await almostExpired.lookup(for: account, videos: [video], folders: [folder]).folderIDs == [video.id: folder.id])
        let expired = makeCache(directory, offset: 86_400)
        #expect(await expired.lookup(for: account, videos: [video], folders: [folder]).folderIDs.isEmpty)
    }

    @Test func capacityIsPerAccountAndARequestInFlightCannotRepopulateAfterSignOut() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = makeCache(directory)
        let videos = (0..<101).map { LibraryFixtures.video(url: "https://www.tiktok.com/@maker/video/\($0)") }
        let updates = videos.map { FolderSuggestionCache.Update(videoID: $0.id, folderID: folder.id) }
        let first = await cache.lookup(for: account, videos: videos, folders: [folder])
        await cache.save(updates, from: first)
        let secondAccount = UUID()
        let other = await cache.lookup(for: secondAccount, videos: videos, folders: [folder])
        await cache.save(Array(updates.prefix(1)), from: other)

        let reopened = makeCache(directory)
        let inFlight = await reopened.lookup(for: account, videos: videos, folders: [folder])
        #expect(inFlight.folderIDs.count == 100)
        await reopened.clear(for: account)
        await reopened.save(updates, from: inFlight)

        let nextLaunch = makeCache(directory)
        #expect(await nextLaunch.lookup(for: account, videos: videos, folders: [folder]).folderIDs.isEmpty)
        #expect(await nextLaunch.lookup(for: secondAccount, videos: videos, folders: [folder]).folderIDs.count == 1)
    }

    @Test func reopeningOfflineShowsCachedCardsAndAcceptQueuesTheMove() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = LibraryFixtures.video(tags: ["design"])
        let uncached = LibraryFixtures.video(url: "https://www.tiktok.com/@uncached/video/2")
        let videoRepository = V3SimulatedLibrary(videos: [video], folders: [folder])
        let pipeline = CountingPipeline(folder: folder.name)
        let first = SmartOrganizationViewModel(
            videoRepository: videoRepository, folderRepository: videoRepository,
            suggestionPipeline: pipeline, cache: makeCache(directory), accountID: account
        )
        await first.load()
        #expect(first.suggestions.map(\.id) == [video.id])
        #expect(pipeline.calls == [video.sourceURL])

        let offlineDirectory = directory.appending(path: "offline")
        let libraryStore = LocalLibraryStore(directory: offlineDirectory)
        let folder = self.folder
        try await libraryStore.updatePersisted { _ in .init(videos: [video, uncached], folders: [folder]) }
        let queue = PendingActionQueue(directory: offlineDirectory)
        let offlineRepository = OfflineFirstLibraryRepository(
            videosAPI: videoRepository, foldersAPI: videoRepository,
            playbackAPI: MockVideoPlaybackRepository(videoRepository: videoRepository),
            store: libraryStore, queue: queue, memory: LibraryMemoryCache(),
            isOnline: { false }, networkType: { .offline }
        )
        let reopened = SmartOrganizationViewModel(
            videoRepository: offlineRepository, folderRepository: offlineRepository,
            suggestionPipeline: pipeline, cache: makeCache(directory), accountID: account
        )
        await reopened.load(isOnline: { false })
        #expect(reopened.cachedSuggestionIDs == [video.id])
        #expect(reopened.connectionNeeded == [uncached.id])
        #expect(pipeline.calls == [video.sourceURL])

        let card = try #require(reopened.suggestions.first)
        #expect(await reopened.accept(card))
        let actions = await queue.all()
        #expect(actions.first?.videoID == video.id)
        #expect(actions.first?.kind == .move(folderID: folder.id))
        #expect(reopened.unorganizedCount == 1)
        #expect(reopened.suggestions.isEmpty)
    }

    @Test func manualRefreshBypassesHitsAndKeepsThemWhenTheConnectionDrops() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = LibraryFixtures.video()
        let other = LibraryFolder(id: UUID(), name: "Ideas", symbolName: "folder")
        let repository = V3SimulatedLibrary(videos: [video], folders: [folder, other])
        let pipeline = CountingPipeline(folder: folder.name)
        let model = SmartOrganizationViewModel(
            videoRepository: repository, folderRepository: repository,
            suggestionPipeline: pipeline, cache: makeCache(directory), accountID: account
        )
        await model.load()
        await model.refresh(isOnline: { true }, bypassCache: false)
        #expect(pipeline.calls.count == 1)
        #expect(model.cachedSuggestionIDs == [video.id])

        pipeline.response = .failure(APIClientError.networkUnavailable)
        await model.refresh(isOnline: { true })
        #expect(pipeline.calls.count == 2)
        #expect(model.cachedSuggestionIDs == [video.id])
        #expect(model.suggestions.first?.folder == folder)

        pipeline.response = .success(other.name)
        await model.refresh(isOnline: { true })
        #expect(pipeline.calls.count == 3)
        #expect(model.cachedSuggestionIDs.isEmpty)
        #expect(model.suggestions.first?.folder == other)

        pipeline.response = .success(nil)
        await model.refresh(isOnline: { true })
        let reopened = makeCache(directory)
        #expect(await reopened.lookup(for: account, videos: [video], folders: [folder, other]).folderIDs.isEmpty)
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "suggestions-\(UUID())", directoryHint: .isDirectory)
    }

    private func makeCache(_ directory: URL, offset: TimeInterval = 0) -> FolderSuggestionCache {
        let date = now.addingTimeInterval(offset)
        return FolderSuggestionCache(directory: directory, now: { date })
    }

    @MainActor
    private final class CountingPipeline: VideoImportPipeline {
        var response: Result<String?, any Error>
        private(set) var calls: [URL] = []
        private let mock = MockVideoImportPipeline(delay: .zero)

        init(folder: String) { response = .success(folder) }

        func detectPlatform(from sourceURL: URL) async throws -> VideoPlatform {
            try await mock.detectPlatform(from: sourceURL)
        }

        func extractMetadata(from sourceURL: URL, platform: VideoPlatform) async throws -> ImportedVideoMetadata {
            try await mock.extractMetadata(from: sourceURL, platform: platform)
        }

        func generateTags(for metadata: ImportedVideoMetadata) async throws -> [String] { [] }

        func suggestFolder(for metadata: ImportedVideoMetadata, tags: [String]) async throws -> String? {
            calls.append(metadata.sourceURL)
            return try response.get()
        }
    }
}
