import Foundation
import Testing
@testable import Centralia

@MainActor
struct SavedSearchTests {
    @Test func storesAllFiltersAndKeepsAccountsSeparateAcrossReopens() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstID = UUID()
        let secondID = UUID()
        let folderID = UUID()
        let criteria = VideoSearchCriteria(
            text: "ceramics", platform: .instagramReel, creator: "@studio", folder: .folder(folderID), tags: ["Clay", "craft"]
        )
        let firstStore = SavedSearchStore(directory: directory)
        let created = try await firstStore.create(named: "  Workshop  ", criteria: criteria, for: firstID)
        let saved = try #require(created.first)
        _ = try await firstStore.create(named: "Explore", criteria: .init(folder: .unorganized), for: secondID)

        let reopened = SavedSearchStore(directory: directory)
        let searches = try await reopened.searches(for: firstID)
        #expect(searches == [saved])
        #expect(searches.first?.name == "Workshop")
        #expect(searches.first?.criteria == criteria)
        #expect(try await reopened.searches(for: secondID).map(\.name) == ["Explore"])

        let renamed = try await reopened.rename(saved.id, to: "New workshop", for: firstID)
        #expect(renamed.first?.criteria == criteria)
        #expect(try await SavedSearchStore(directory: directory).searches(for: firstID).map(\.name) == ["New workshop"])

        _ = try await reopened.remove(saved.id, for: firstID)
        let nextLaunch = SavedSearchStore(directory: directory)
        #expect(try await nextLaunch.searches(for: firstID).isEmpty)
        #expect(try await nextLaunch.searches(for: secondID).map(\.name) == ["Explore"])
    }

    @Test func concurrentCreatesKeepBothSearchesAndUnreadableFilesArePreserved() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SavedSearchStore(directory: directory)
        let userID = UUID()
        async let first = store.create(named: "Clay", criteria: .init(tags: ["clay"]), for: userID)
        async let second = store.create(named: "Tools", criteria: .init(text: "tools"), for: userID)
        _ = try await (first, second)
        #expect(Set(try await store.searches(for: userID).map(\.name)) == ["Clay", "Tools"])

        let url = directory.appending(path: "\(userID.uuidString).json")
        let damaged = Data("unreadable JSON".utf8)
        try damaged.write(to: url)
        await #expect(throws: DecodingError.self) {
            try await store.create(named: "New", criteria: .init(text: "new"), for: userID)
        }
        #expect(try Data(contentsOf: url) == damaged)
    }

    @Test func reappliesFiltersToTheOfflineLibraryAndKeepsAMissingFolderSelected() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = LibraryFolder(id: UUID(), name: "Design", symbolName: "folder")
        let match = LibraryFixtures.video(creator: "@maker", folderID: folder.id, tags: ["clay"])
        let other = LibraryFixtures.video(creator: "@maker", tags: ["clay"])
        let libraryDirectory = directory.appending(path: "offline")
        let libraryStore = LocalLibraryStore(directory: libraryDirectory)
        await libraryStore.update { _ in .init(videos: [match, other], folders: [folder]) }
        let searchStore = SavedSearchStore(directory: directory.appending(path: "searches"))
        let account = UUID()
        _ = try await searchStore.create(
            named: "Folder search",
            criteria: .init(text: "maker", platform: match.platform, creator: "@maker", folder: .folder(folder.id), tags: ["clay"]),
            for: account
        )
        let reopenedStore = SavedSearchStore(directory: directory.appending(path: "searches"))
        let searches = try await reopenedStore.searches(for: account)
        let saved = try #require(searches.first)

        let offline = offlineModel(libraryDirectory: libraryDirectory)
        await offline.load()
        offline.applySavedSearch(saved)
        #expect(offline.criteria == saved.criteria)
        #expect(offline.filteredVideos.map(\.id) == [match.id])

        await libraryStore.update { snapshot in
            var snapshot = snapshot
            snapshot.folders = []
            return snapshot
        }
        let afterFolderRemoval = offlineModel(libraryDirectory: libraryDirectory)
        await afterFolderRemoval.load()
        afterFolderRemoval.applySavedSearch(saved)
        #expect(afterFolderRemoval.selectedFolderIsUnavailable)
        #expect(afterFolderRemoval.selectedFolder == .folder(folder.id))
        #expect(afterFolderRemoval.filteredVideos.isEmpty)
        afterFolderRemoval.selectedFolder = .all
        #expect(afterFolderRemoval.query == "maker")
        #expect(afterFolderRemoval.selectedTags == ["clay"])
        #expect(afterFolderRemoval.filteredVideos.map(\.id).contains(other.id))
    }

    private func offlineModel(libraryDirectory: URL) -> SearchViewModel {
        let client = APILibraryClient(api: APIClient(configuration: APIConfiguration(baseURL: nil)))
        let library = OfflineFirstLibraryRepository(
            videosAPI: APIVideoItemRepository(client: client),
            foldersAPI: APIFolderRepository(client: client),
            playbackAPI: APIVideoPlaybackRepository(client: client),
            store: LocalLibraryStore(directory: libraryDirectory),
            queue: PendingActionQueue(directory: libraryDirectory),
            memory: LibraryMemoryCache(),
            isOnline: { false },
            networkType: { .offline }
        )
        return SearchViewModel(videoRepository: library, folderRepository: library, searchHistoryRepository: UnusedHistory())
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private struct UnusedHistory: SearchHistoryRepository {
        func recentSearches() async throws -> [String] { [] }
        func recordSearch(_ query: String) async throws { Issue.record("Applying a saved search must not write remote history") }
        func clearSearchHistory() async throws {}
    }
}
