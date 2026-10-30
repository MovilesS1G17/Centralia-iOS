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
    private let onSynced: @MainActor @Sendable () -> Void
    private var isSyncing = false
    private var syncAgain = false

    init(
        queue: PendingActionQueue,
        send: @escaping @Sendable (PendingAction) async throws -> Void,
        onSynced: @escaping @MainActor @Sendable () -> Void
    ) {
        self.queue = queue
        self.send = send
        self.onSynced = onSynced
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
            for action in await queue.all() {
                do {
                    try await send(action)
                    await queue.remove(action)
                    synced += 1
                } catch {
                    guard Self.isPermanentFailure(error) else { break }
                    await queue.remove(action)
                }
            }
        } while syncAgain
        if synced > 0 { await onSynced() }
        return synced
    }

    /// 4xx answers (except timeouts and rate limits) will never succeed.
    nonisolated static func isPermanentFailure(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError,
              case let .server(status, _, _, _, _) = apiError else { return false }
        return (400...499).contains(status) && status != 408 && status != 429
    }
}
