import Foundation
import Testing
@testable import Centralia

@MainActor
struct FolderRenameSyncTests {
    @Test func creatingAFolderPublishesItAndKeepsItAvailableOffline() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanUp() }
        harness.isOnline = true
        let status = OfflineStatus()
        status.activate(accountID: harness.userID)
        let repository = harness.repository(onFolderChange: status.updateFolders)

        let folder = try await repository.createFolder(named: "New inspiration", symbolName: "folder")

        #expect(status.folderSnapshot?.contains(folder) == true)
        #expect(status.folderSnapshot?.contains(harness.folder) == true)
        #expect(await harness.store().read().folders.contains(folder))
        harness.isOnline = false
        let reopened = try await harness.repository().folders()
        #expect(reopened.contains(folder))
    }

    @Test func newestNameSurvivesRestartAndIsConfirmedBeforeDroppingTheOutboxEntry() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanUp() }
        let id = harness.folder.id

        _ = try await harness.repository().renameFolder(id: id, to: "Draft")
        let renamed = try await harness.repository().renameFolder(id: id, to: " Workshop ")
        #expect(renamed.name == "Workshop")
        #expect(await harness.store().read().folders.first?.name == "Design")

        let reopenedQueue = harness.queue()
        let pending = await reopenedQueue.all()
        #expect(pending.count == 1)
        #expect(pending.first?.folderRename?.name == "Workshop")
        #expect(pending.first?.folderRename?.userID == harness.userID)
        let reopened = harness.repository(queue: reopenedQueue)
        #expect(try await reopened.folders().first(where: { $0.id == id })?.name == "Workshop")

        harness.isOnline = true
        #expect(await harness.sync(repository: reopened, queue: reopenedQueue).sync() == 1)
        #expect(harness.remote.sentNames == ["Workshop"])
        #expect(await reopenedQueue.all().isEmpty)
        harness.isOnline = false
        #expect(try await harness.repository().folders().first(where: { $0.id == id })?.name == "Workshop")
    }

    @Test func serverConflictRestoresTheAuthoritativeNameWithoutClearingDetailFilters() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanUp() }
        let queue = harness.queue()
        let repository = harness.repository(queue: queue)
        let detail = FolderDetailViewModel(folder: harness.folder, videoRepository: harness.videos, folderRepository: repository)
        await detail.load()
        detail.query = "wheel"
        detail.selectedSourceFilter = .platform(.instagramReel)
        detail.sort = .alphabetical
        #expect(await detail.renameFolder(to: "Studio"))

        harness.remote.foldersOnServer[0].name = "Current on server"
        harness.remote.foldersOnServer[1].name = "Studio"
        harness.isOnline = true
        #expect(await harness.sync(repository: repository, queue: queue).sync() == 0)
        #expect(harness.notices == [.nameTaken])
        #expect(await queue.all().isEmpty)

        harness.isOnline = false
        detail.applyFolderSnapshot(try await repository.folders())
        #expect(detail.folder.name == "Current on server")
        #expect(detail.query == "wheel")
        #expect(detail.selectedSourceFilter == .platform(.instagramReel))
        #expect(detail.sort == .alphabetical)
    }

    @Test func pendingChangesAreScopedToTheirAccountAndDeletedFoldersLeaveTheSnapshot() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanUp() }
        let queue = harness.queue()
        let repository = harness.repository(queue: queue)
        let id = harness.folder.id
        let video = LibraryFixtures.video(folderID: id)
        try await harness.store().updatePersisted { snapshot in
            var snapshot = snapshot
            snapshot.videos = [video]
            return snapshot
        }
        _ = try await repository.renameFolder(id: id, to: "Studio")
        let owner = harness.userID

        harness.userID = UUID()
        #expect(try await repository.folders().first(where: { $0.id == id })?.name == "Design")
        harness.isOnline = true
        let sync = harness.sync(repository: repository, queue: queue)
        #expect(await sync.sync() == 0)
        #expect(harness.remote.sentNames.isEmpty)
        #expect(await queue.all().count == 1)

        harness.userID = owner
        harness.remote.foldersOnServer.removeAll { $0.id == id }
        #expect(await sync.sync() == 0)
        #expect(harness.notices == [.folderRemoved])
        #expect(await queue.all().isEmpty)
        harness.isOnline = false
        #expect(try await repository.folders().allSatisfy { $0.id != id })
        let videos = try await repository.videos()
        #expect(videos.map(\.id) == [video.id])
        #expect(videos.first?.folderID == nil)
    }

    @Test func aFailedDurableWriteNeverPublishesAnOptimisticName() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanUp() }
        let blocked = harness.directory.appending(path: "file-instead-of-directory")
        try Data("blocked".utf8).write(to: blocked)
        let queue = PendingActionQueue(directory: blocked)
        let repository = harness.repository(queue: queue)

        await #expect(throws: OfflineError.renameNotStored) {
            try await repository.renameFolder(id: harness.folder.id, to: "Workshop")
        }
        #expect(try await repository.folders().first?.name == "Design")
        #expect(await queue.all().isEmpty)
    }

    @Test func aConnectionLossDuringAnOnlineRenameQueuesItForRetry() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanUp() }
        let queue = harness.queue()
        let repository = harness.repository(queue: queue)
        let id = harness.folder.id
        harness.isOnline = true
        harness.remote.renameError = .networkUnavailable

        #expect(try await repository.renameFolder(id: id, to: "Studio").name == "Studio")
        let sync = harness.sync(repository: repository, queue: queue)
        #expect(await sync.sync() == 0)
        #expect(await queue.all().first?.folderRename?.name == "Studio")
        #expect(harness.notices.isEmpty)

        harness.remote.renameError = nil
        #expect(await sync.sync() == 1)
        #expect(await queue.all().isEmpty)
        #expect(harness.remote.foldersOnServer.first(where: { $0.id == id })?.name == "Studio")
    }

    @Test func legacyVideoEntriesStillLoadAlongsideFolderRenames() async throws {
        let harness = try await Harness.make()
        defer { harness.cleanUp() }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let id = harness.folder.id
        let data = Data("""
        [{"videoID":"\(id)","queuedAt":"2027-01-15T08:00:00Z","kind":{"tags":{"_0":["clay"]}}}]
        """.utf8)
        try data.write(to: harness.directory.appending(path: "outbox.json"))
        let queue = harness.queue()
        let legacy = PendingAction(videoID: id, queuedAt: date, kind: .tags(["clay"]))
        #expect(await queue.all() == [legacy])
        _ = try await harness.repository(queue: queue).renameFolder(id: id, to: "Studio")
        let entries = await harness.queue().all()
        #expect(entries.first == legacy)
        #expect(entries.last?.folderRename?.name == "Studio")
    }

    @MainActor
    private final class Harness {
        let directory = URL.temporaryDirectory.appending(path: "folder-sync-\(UUID())", directoryHint: .isDirectory)
        let folder = LibraryFolder(id: UUID(), name: "Design", symbolName: "folder")
        let other = LibraryFolder(id: UUID(), name: "Other", symbolName: "folder")
        let videos = V3SimulatedLibrary()
        let remote = FolderRemote()
        var isOnline = false
        var userID = UUID()
        var notices: [FolderRenameNotice] = []

        static func make() async throws -> Harness {
            let harness = Harness()
            let folders = [harness.folder, harness.other]
            harness.remote.foldersOnServer = folders
            try await harness.store().updatePersisted { _ in .init(folders: folders) }
            return harness
        }

        func store() -> LocalLibraryStore { LocalLibraryStore(directory: directory) }
        func queue() -> PendingActionQueue { PendingActionQueue(directory: directory) }

        func repository(
            queue: PendingActionQueue? = nil,
            onFolderChange: @escaping ([LibraryFolder], UUID) -> Void = { _, _ in }
        ) -> OfflineFirstLibraryRepository {
            OfflineFirstLibraryRepository(
                videosAPI: videos,
                foldersAPI: remote,
                playbackAPI: MockVideoPlaybackRepository(videoRepository: videos),
                store: store(),
                queue: queue ?? self.queue(),
                memory: LibraryMemoryCache(),
                isOnline: { self.isOnline },
                networkType: { .offline },
                currentAccountID: { self.userID },
                onFolderChange: onFolderChange
            )
        }

        func sync(repository: OfflineFirstLibraryRepository, queue: PendingActionQueue) -> SyncManager {
            SyncManager(
                queue: queue,
                canSend: { ($0.folderRename?.userID == self.userID) && self.isOnline },
                send: { action in
                    if let rename = action.folderRename {
                        try await repository.replayFolderRename(rename, queuedAt: action.queuedAt)
                    }
                },
                onRenameSettled: { _, notice in
                    if let notice { self.notices.append(notice) }
                },
                onSynced: {}
            )
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    private final class FolderRemote: FolderRepository {
        var foldersOnServer: [LibraryFolder] = []
        var renameError: APIClientError?
        private(set) var sentNames: [String] = []

        func folders() async throws -> [LibraryFolder] { foldersOnServer }

        func renameFolder(id: UUID, to name: String) async throws -> LibraryFolder {
            sentNames.append(name)
            if let renameError { throw renameError }
            guard let index = foldersOnServer.firstIndex(where: { $0.id == id }) else {
                throw APIClientError.server(status: 404, code: "folder_not_found", detail: "Folder unavailable", email: nil, retryAfter: nil)
            }
            if foldersOnServer.contains(where: { $0.id != id && $0.name == name }) {
                throw APIClientError.server(status: 409, code: "folder_name_duplicate", detail: "Name already used", email: nil, retryAfter: nil)
            }
            foldersOnServer[index].name = name
            return foldersOnServer[index]
        }

        func createFolder(named name: String, symbolName: String) async throws -> LibraryFolder {
            let folder = LibraryFolder(id: UUID(), name: name, symbolName: symbolName)
            foldersOnServer.append(folder)
            return folder
        }

        func deleteFolder(id: UUID) async throws { foldersOnServer.removeAll { $0.id == id } }
    }
}
