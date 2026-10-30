import Foundation

/// Eventual connectivity + caching + local storage (Sprint 3) for the library.
/// It wraps the API repositories, so the screens and view models don't change:
///
/// | Data | Strategy |
/// |---|---|
/// | Library and folder lists | Network falling back to cache: memory, then the JSON file on disk |
/// | Delete, undo, move, note, tags | Offline: applied to the local copy at once and queued in the outbox; synced when the network is back |
/// | Playback | Cache (10 min) falling back to network; offline it needs a connection |
/// | Saving a short, creating/renaming/deleting folders | Network only, with a clear "you're offline" message |
///
/// The disk copy is written in a separate `Task` on the store's actor, so the
/// screen gets its answer without waiting for the file. Mirrors
/// `OfflineFirstLibraryRepository` on Android.
final class OfflineFirstLibraryRepository: VideoItemRepository, FolderRepository, VideoPlaybackRepository {
    private let videosAPI: APIVideoItemRepository
    private let foldersAPI: APIFolderRepository
    private let playbackAPI: APIVideoPlaybackRepository
    private let store: LocalLibraryStore
    private let queue: PendingActionQueue
    private let memory: LibraryMemoryCache
    private let isOnline: () -> Bool
    private let networkType: () -> NetworkType
    private let now: () -> Date

    init(
        videosAPI: APIVideoItemRepository,
        foldersAPI: APIFolderRepository,
        playbackAPI: APIVideoPlaybackRepository,
        store: LocalLibraryStore,
        queue: PendingActionQueue,
        memory: LibraryMemoryCache,
        isOnline: @escaping () -> Bool,
        networkType: @escaping () -> NetworkType,
        now: @escaping () -> Date = Date.init
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
            do {
                let fresh = try await foldersAPI.folders()
                memory.folders = fresh
                let savedAt = now()
                Task { await store.update { snapshot in
                    var copy = snapshot
                    copy.folders = fresh
                    copy.savedAt = savedAt
                    return copy
                } }
                return fresh
            } catch where APIClientError.isOffline(error) {
                // Fall through to the saved copy.
            }
        }
        if let cached = memory.folders { return cached }
        let saved = await store.read().folders
        memory.folders = saved
        return saved
    }

    func playback(for videoID: UUID) async throws -> VideoPlayback {
        let network = networkType()
        if let cached = memory.playback(for: videoID, network: network) { return cached }
        guard isOnline() else { throw OfflineError.needsConnection("Playing a short") }
        let fresh = try await networkOnly("Playing a short") { try await playbackAPI.playback(for: videoID) }
        memory.store(fresh, for: videoID, network: network)
        return fresh
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
        try await networkOnly("Creating a folder") {
            try await foldersAPI.createFolder(named: name, symbolName: symbolName)
        }
    }

    func renameFolder(id: UUID, to name: String) async throws -> LibraryFolder {
        try await networkOnly("Renaming a folder") { try await foldersAPI.renameFolder(id: id, to: name) }
    }

    func deleteFolder(id: UUID) async throws {
        try await networkOnly("Deleting a folder") { try await foldersAPI.deleteFolder(id: id) }
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
}
