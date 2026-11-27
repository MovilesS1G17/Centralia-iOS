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
    private let onChange: @Sendable ([PendingAction], Int) -> Void
    private var revision = 0
    private let encoder = OfflineJSON.encoder()
    private let decoder = OfflineJSON.decoder()

    init(
        directory: URL = LocalLibraryStore.defaultDirectory,
        onChange: @escaping @Sendable ([PendingAction], Int) -> Void = { _, _ in }
    ) {
        fileURL = directory.appending(path: "outbox.json")
        self.onChange = onChange
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

    func enqueueFolderRename(_ action: PendingAction) throws {
        let updated = PendingAction.enqueue(action, into: try readPersisted())
        try persist(updated)
        publish(updated)
    }

    func contains(_ action: PendingAction) -> Bool { all().contains(action) }

    func removeProcessed(_ action: PendingAction) throws -> Bool {
        let current = all()
        guard current.contains(action) else { return false }
        let updated = current.filter { $0 != action }
        if action.folderRename != nil {
            try persist(updated)
            publish(updated)
        } else {
            save(updated)
        }
        return true
    }

    func clear() {
        save([])
    }

    func publishState() {
        publish(all())
    }

    private func save(_ updated: [PendingAction]) {
        try? persist(updated)
        publish(updated)
    }

    private func publish(_ updated: [PendingAction]) {
        actions = updated
        revision += 1
        onChange(updated, revision)
    }

    private func readPersisted() throws -> [PendingAction] {
        do {
            let saved = try decoder.decode([PendingAction].self, from: Data(contentsOf: fileURL))
            return actions ?? saved
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return actions ?? []
        }
    }

    private func persist(_ updated: [PendingAction]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try encoder.encode(updated).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
