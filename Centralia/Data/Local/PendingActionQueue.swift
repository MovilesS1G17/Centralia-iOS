import Foundation

/// Eventual connectivity + local storage (Sprint 3): the outbox of changes made
/// offline, kept in `offline/outbox.json` so they survive closing the app or
/// restarting the phone. `SyncManager` empties it when the network is back.
///
/// An `actor`: the screens and the sync manager can touch it at the same time
/// without races. `onCountChange` reports how many changes are waiting (for the
/// offline banner). Mirrors `PendingActionQueue` on Android.
actor PendingActionQueue {
    private let fileURL: URL
    private var actions: [PendingAction]?
    private let onCountChange: @Sendable (Int) -> Void
    private let encoder = OfflineJSON.encoder()
    private let decoder = OfflineJSON.decoder()

    init(
        directory: URL = LocalLibraryStore.defaultDirectory,
        onCountChange: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        fileURL = directory.appending(path: "outbox.json")
        self.onCountChange = onCountChange
    }

    func all() -> [PendingAction] {
        if let actions { return actions }
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? decoder.decode([PendingAction].self, from: $0) } ?? []
        actions = loaded
        return loaded
    }

    func enqueue(_ action: PendingAction) {
        save(PendingAction.enqueue(action, into: all()))
    }

    func remove(_ action: PendingAction) {
        save(all().filter { $0 != action })
    }

    func clear() {
        save([])
    }

    func refreshCount() {
        onCountChange(all().count)
    }

    private func save(_ updated: [PendingAction]) {
        actions = updated
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try encoder.encode(updated).write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // Kept in memory; written again with the next change.
        }
        onCountChange(updated.count)
    }
}
