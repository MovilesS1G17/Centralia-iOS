import Foundation

/// Eventual connectivity + caching + local storage (Sprint 3) for the library.
/// It wraps the API repositories, so the screens and view models don't change:
///
/// | Data | Strategy |
/// |---|---|
/// | Library and folder lists | Network falling back to cache: memory, then the JSON file on disk |
/// | Delete, undo, move, note, tags | Offline: applied to the local copy at once and queued in the outbox; synced when the network is back |
/// | Playback | Cache (10 min) falling back to network; offline it needs a connection |
/// | Rename a folder | Confirm online or project the account's durable pending rename |
/// | Saving a short, creating/deleting folders | Network only, with a clear "you're offline" message |
///
/// The disk copy is written in a separate `Task` on the store's actor, so the
/// screen gets its answer without waiting for the file. Mirrors
/// `OfflineFirstLibraryRepository` on Android.
final class OfflineFirstLibraryRepository: VideoItemRepository, FolderRepository, VideoPlaybackRepository {
    private let videosAPI: any VideoItemRepository
    private let foldersAPI: any FolderRepository
    private let playbackAPI: any VideoPlaybackRepository
    private let store: LocalLibraryStore
    private let queue: PendingActionQueue
    private let memory: LibraryMemoryCache
    private let isOnline: () -> Bool
    private let networkType: () -> NetworkType
    private let now: () -> Date
    private let currentAccountID: () -> UUID?
    private let onFolderChange: ([LibraryFolder], UUID) -> Void
    private let onRenameQueued: (PendingAction.FolderRename) -> Void
    private var folderRevision = 0

    init(
        videosAPI: any VideoItemRepository,
        foldersAPI: any FolderRepository,
        playbackAPI: any VideoPlaybackRepository,
        store: LocalLibraryStore,
        queue: PendingActionQueue,
        memory: LibraryMemoryCache,
        isOnline: @escaping () -> Bool,
        networkType: @escaping () -> NetworkType,
        now: @escaping () -> Date = Date.init,
        currentAccountID: @escaping () -> UUID? = { nil },
        onFolderChange: @escaping ([LibraryFolder], UUID) -> Void = { _, _ in },
        onRenameQueued: @escaping (PendingAction.FolderRename) -> Void = { _ in }
    ) {
        self.videosAPI = videosAPI
        self.foldersAPI = foldersAPI
        self.playbackAPI = playbackAPI
        self.store = store
        self.queue = queue
        self.memory = memory
        self.isOnline = isOnline
        self.networkType = networkType
        self.now = now
        self.currentAccountID = currentAccountID
        self.onFolderChange = onFolderChange
        self.onRenameQueued = onRenameQueued
    }

    // MARK: Reads

    func videos() async throws -> [VideoItem] {
        if isOnline() {
            do {
                let fresh = try await videosAPI.videos()
                memory.videos = fresh
                let savedAt = now()
                Task { await store.update { snapshot in
                    var copy = snapshot
                    copy.videos = fresh
                    copy.savedAt = savedAt
                    return copy
                } }
                return await withPendingChanges(fresh)
            } catch where APIClientError.isOffline(error) {
                // Fall through to the saved copy.
            }
        }
        if let cached = memory.videos { return await withPendingChanges(cached) }
        let saved = await store.read().videos
        memory.videos = saved
        return await withPendingChanges(saved)
    }

    func folders() async throws -> [LibraryFolder] {
        if isOnline() {
            let revision = folderRevision
            do {
                let fresh = try await foldersAPI.folders()
                if revision == folderRevision {
                    memory.folders = fresh
                    let savedAt = now()
                    await store.update { snapshot in
                        var copy = snapshot
                        copy.folders = fresh
                        copy.savedAt = savedAt
                        return copy
                    }
                }
            } catch where APIClientError.isOffline(error) {
                // Fall through to the saved copy.
            }
        }
        return await projectedFolders()
    }

    func playback(for videoID: UUID) async throws -> VideoPlayback {
        let network = networkType()
        if let cached = memory.playback(for: videoID, network: network) { return cached }
        guard isOnline() else { throw OfflineError.needsConnection("Playing a short") }
        let fresh = try await networkOnly("Playing a short") { try await playbackAPI.playback(for: videoID) }
        memory.store(fresh, for: videoID, network: network)
        return fresh
    }

    func standardPlayback(for videoID: UUID) async throws -> VideoPlayback {
        try await networkOnly("Playing a short") { try await playbackAPI.standardPlayback(for: videoID) }
    }

    func recordSourceOpened(id: UUID) async {
        guard isOnline() else { return }
        await videosAPI.recordSourceOpened(id: id)
    }

    // MARK: Network only

    func saveVideo(_ video: VideoItem) async throws {
        try await networkOnly("Saving a short") { try await videosAPI.saveVideo(video) }
        memory.videos = nil // the next read goes to the network
    }

    func createFolder(named name: String, symbolName: String) async throws -> LibraryFolder {
        let accountID = currentAccountID()
        let folder = try await networkOnly("Creating a folder") {
            try await foldersAPI.createFolder(named: name, symbolName: symbolName)
        }
        try requireCurrentAccount(accountID)
        try await cacheFolder(folder.id, as: folder, durable: false)
        try requireCurrentAccount(accountID)
        if let accountID { await publishFolders(for: accountID) }
        return folder
    }

    func renameFolder(id: UUID, to name: String) async throws -> LibraryFolder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FolderRepositoryError.emptyName }

        let accountID = currentAccountID()
        let pendingForFolder = await queue.all().contains {
            $0.folderRename?.folderID == id && $0.folderRename?.userID == accountID
        }
        try requireCurrentAccount(accountID)
        if isOnline(), !pendingForFolder {
            do {
                let folder = try await foldersAPI.renameFolder(id: id, to: trimmed)
                try requireCurrentAccount(accountID)
                try await cacheFolder(id, as: folder, durable: false)
                if let accountID { await publishFolders(for: accountID) }
                return folder
            } catch where APIClientError.isOffline(error) {
                // The same desired name can be replayed even if the response was lost.
            }
        }

        guard let accountID else { throw OfflineError.needsConnection("Renaming a folder") }
        let folders = await projectedFolders()
        try requireCurrentAccount(accountID)
        guard var folder = folders.first(where: { $0.id == id }) else { throw FolderRepositoryError.folderNotFound }
        guard let confirmed = memory.folders?.first(where: { $0.id == id }) else { throw FolderRepositoryError.folderNotFound }
        let pendingName = String(trimmed.unicodeScalars.prefix(120))
        guard !folders.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(pendingName) == .orderedSame }) else {
            throw FolderRepositoryError.duplicateName
        }
        let action = PendingAction(folderID: id, userID: accountID, name: pendingName, queuedAt: now())
        do {
            try await store.updatePersisted { snapshot in
                var snapshot = snapshot
                if !snapshot.folders.contains(where: { $0.id == id }) { snapshot.folders.append(confirmed) }
                return snapshot
            }
            try requireCurrentAccount(accountID)
            try await queue.enqueueFolderRename(action)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OfflineError.renameNotStored
        }

        await publishFolders(for: accountID)
        try requireCurrentAccount(accountID)
        if let rename = action.folderRename { onRenameQueued(rename) }
        folder.name = pendingName
        return folder
    }

    func deleteFolder(id: UUID) async throws {
        let accountID = currentAccountID()
        try await networkOnly("Deleting a folder") { try await foldersAPI.deleteFolder(id: id) }
        try requireCurrentAccount(accountID)
        try await cacheFolder(id, as: nil, durable: false)
        if let accountID {
            for action in await queue.all() where action.folderRename?.folderID == id && action.folderRename?.userID == accountID {
                _ = try? await queue.removeProcessed(action)
            }
            await publishFolders(for: accountID)
        }
    }

    func replayFolderRename(_ rename: PendingAction.FolderRename, queuedAt: Date) async throws {
        try requireCurrentAccount(rename.userID)
        do {
            let folder = try await foldersAPI.renameFolder(id: rename.folderID, to: rename.name, queuedAt: queuedAt)
            try requireCurrentAccount(rename.userID)
            try await cacheFolder(rename.folderID, as: folder, durable: true)
        } catch where SyncManager.isPermanentFailure(error) {
            try requireCurrentAccount(rename.userID)
            if FolderRenameNotice(error: error) == .folderRemoved {
                try await cacheFolder(rename.folderID, as: nil, durable: true)
            } else if let fresh = try? await foldersAPI.folders() {
                try requireCurrentAccount(rename.userID)
                try await cacheFolder(rename.folderID, as: fresh.first { $0.id == rename.folderID }, durable: true)
            }
            throw error
        }
    }

    func publishFolders(for accountID: UUID) async {
        let folders = await projectedFolders()
        guard accountID == currentAccountID() else { return }
        onFolderChange(folders, accountID)
    }

    // MARK: Queued when offline

    @discardableResult
    func deleteVideo(id: UUID) async throws -> VideoDeletion {
        let action = PendingAction(videoID: id, queuedAt: now(), kind: .delete)
        return try await orQueue(action) { try await videosAPI.deleteVideo(id: id) }
            ?? VideoDeletion.local(videoID: id, now: now())
    }

    func restoreVideo(_ video: VideoItem) async throws {
        try await restoreVideo(video, method: .button)
    }

    func restoreVideo(_ video: VideoItem, method: UndoMethod) async throws {
        let action = PendingAction(videoID: video.id, queuedAt: now(), kind: .restore(method: method))
        let sent: Void? = try await orQueue(action) { try await videosAPI.restoreVideo(video, method: method) }
        if sent == nil {
            // Offline: put the short back in the local copy right away.
            await updateLocal { videos in videos.filter { $0.id != video.id } + [video] }
        }
    }

    func moveVideo(id: UUID, to folderID: UUID?) async throws {
        let action = PendingAction(videoID: id, queuedAt: now(), kind: .move(folderID: folderID))
        _ = try await orQueue(action) { try await videosAPI.moveVideo(id: id, to: folderID) }
    }

    func updateNote(id: UUID, note: String?) async throws {
        let action = PendingAction(videoID: id, queuedAt: now(), kind: .note(note))
        _ = try await orQueue(action) { try await videosAPI.updateNote(id: id, note: note) }
    }

    func updateTags(id: UUID, tags: [String]) async throws {
        let action = PendingAction(videoID: id, queuedAt: now(), kind: .tags(tags))
        _ = try await orQueue(action) { try await videosAPI.updateTags(id: id, tags: tags) }
    }

    // MARK: Helpers

    /// Tries the server; if the phone is offline, applies `action` to the local
    /// copy, queues it and returns nil so the caller can answer locally.
    private func orQueue<T>(_ action: PendingAction, send: () async throws -> T) async throws -> T? {
        if isOnline() {
            do {
                let result = try await send()
                if let cached = memory.videos { memory.videos = action.apply(to: cached) }
                return result
            } catch where APIClientError.isOffline(error) {
                // Queue it below.
            }
        }
        await queue.enqueue(action)
        await updateLocal { action.apply(to: $0) }
        return nil
    }

    private func updateLocal(_ transform: @escaping @Sendable ([VideoItem]) -> [VideoItem]) async {
        let updated = await store.update { snapshot in
            var copy = snapshot
            copy.videos = transform(snapshot.videos)
            return copy
        }
        memory.videos = updated.videos
    }

    private func networkOnly<T>(_ action: String, send: () async throws -> T) async throws -> T {
        guard isOnline() else { throw OfflineError.needsConnection(action) }
        do {
            return try await send()
        } catch where APIClientError.isOffline(error) {
            throw OfflineError.needsConnection(action)
        }
    }

    /// Changes still in the outbox are shown even when the list came from the server.
    private func withPendingChanges(_ videos: [VideoItem]) async -> [VideoItem] {
        await queue.all().reduce(videos) { list, action in action.apply(to: list) }
    }

    private func projectedFolders() async -> [LibraryFolder] {
        if memory.folders == nil {
            let disk = await store.read().folders
            if memory.folders == nil { memory.folders = disk }
        }
        let actions = await queue.all()
        let accountID = currentAccountID()
        let base = memory.folders ?? []
        let names = actions.compactMap(\.folderRename).filter { $0.userID == accountID }
        return base.map { folder in
            var projected = folder
            if let rename = names.last(where: { $0.folderID == folder.id }) {
                projected.name = rename.name
            }
            return projected
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func cacheFolder(_ id: UUID, as folder: LibraryFolder?, durable: Bool) async throws {
        folderRevision += 1
        let revision = folderRevision
        let unassignVideos: @Sendable ([VideoItem]) -> [VideoItem] = { videos in
            videos.map { video in
                guard video.folderID == id else { return video }
                var video = video
                video.folderID = nil
                return video
            }
        }
        let replace: @Sendable (LocalLibraryStore.Snapshot) -> LocalLibraryStore.Snapshot = { snapshot in
            var copy = snapshot
            copy.folders.removeAll { $0.id == id }
            if let folder {
                copy.folders.append(folder)
            } else {
                copy.videos = unassignVideos(copy.videos)
            }
            return copy
        }
        let updated = if durable { try await store.updatePersisted(replace) } else { await store.update(replace) }
        if revision == folderRevision { memory.folders = updated.folders }
        if folder == nil, let videos = memory.videos { memory.videos = unassignVideos(videos) }
    }

    private func requireCurrentAccount(_ accountID: UUID?) throws {
        guard currentAccountID() == accountID else { throw CancellationError() }
    }
}
