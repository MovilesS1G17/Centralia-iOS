import Foundation

/// Eventual connectivity + multithreading (Sprint 3): sends the outbox to the
/// backend when the phone gets a connection back.
///
/// - An `actor`, so its state is never touched by two threads at once; the
///   `isSyncing` flag makes sure only one sync runs even if the network flaps
///   (the actor can be re-entered while it awaits the network).
/// - Runs in a background `Task`, outside any screen, and never blocks the UI.
/// - Changes go out in the order the user made them. If the network drops
///   again it stops and keeps the rest for next time; a change the server
///   rejects for good (e.g. the short was deleted on another phone, 404) is
///   dropped so it doesn't block the queue.
/// - When something was synced, `onSynced` runs on the main actor so the lists
///   reload with the server's version. Mirrors `SyncManager` on Android.
actor SyncManager {
    private let queue: PendingActionQueue
    private let send: @Sendable (PendingAction) async throws -> Void
    private let canSend: @MainActor @Sendable (PendingAction) -> Bool
    private let onSynced: @MainActor @Sendable () -> Void
    private let onRenameSettled: @MainActor @Sendable (PendingAction.FolderRename, FolderRenameNotice?) async -> Void
    private var isSyncing = false
    private var syncAgain = false

    init(
        queue: PendingActionQueue,
        canSend: @escaping @MainActor @Sendable (PendingAction) -> Bool = { _ in true },
        send: @escaping @Sendable (PendingAction) async throws -> Void,
        onRenameSettled: @escaping @MainActor @Sendable (PendingAction.FolderRename, FolderRenameNotice?) async -> Void = { _, _ in },
        onSynced: @escaping @MainActor @Sendable () -> Void
    ) {
        self.queue = queue
        self.canSend = canSend
        self.send = send
        self.onSynced = onSynced
        self.onRenameSettled = onRenameSettled
    }

    nonisolated func requestSync() {
        Task(priority: .utility) { await self.sync() }
    }

    @discardableResult
    func sync() async -> Int {
        guard !isSyncing else {
            syncAgain = true
            return 0
        }
        isSyncing = true
        defer { isSyncing = false }

        var synced = 0
        repeat {
            syncAgain = false
            var syncedVideos = false
            for action in await queue.all() {
                guard await canSend(action), await queue.contains(action) else { continue }
                let notice: FolderRenameNotice?
                do {
                    try await send(action)
                    notice = nil
                } catch {
                    guard Self.isPermanentFailure(error) else { break }
                    notice = FolderRenameNotice(error: error)
                }

                do {
                    if try await queue.removeProcessed(action) {
                        if notice == nil {
                            synced += 1
                            if action.folderRename == nil { syncedVideos = true }
                        }
                        if let rename = action.folderRename { await onRenameSettled(rename, notice) }
                    }
                } catch {
                    // A folder rename can replay safely if we couldn't commit the removal.
                    break
                }
            }
            if syncedVideos { await onSynced() }
        } while syncAgain
        return synced
    }

    /// 4xx answers (except timeouts and rate limits) will never succeed.
    nonisolated static func isPermanentFailure(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError,
              case let .server(status, _, _, _, _) = apiError else { return false }
        return (400...499).contains(status) && status != 408 && status != 429
    }
}
