import Foundation
import Network
import Observation

/// Eventual connectivity (Sprint 3): what the offline banner shows, read by
/// the screens on the main thread.
@Observable
final class OfflineStatus {
    var isOnline = true
    private(set) var pendingChanges = 0
    private(set) var pendingFolderIDs: Set<UUID> = []
    private(set) var folderRenameNotices: [UUID: FolderRenameNotice] = [:]
    private(set) var folderSnapshot: [LibraryFolder]?
    @ObservationIgnored private var accountID: UUID?
    @ObservationIgnored private var actions: [PendingAction] = []
    @ObservationIgnored private var outboxRevision = 0
    @ObservationIgnored var requestSync: () -> Void = {}
    /// Goes up every time queued changes reach the server, so the lists reload.
    var syncRevision = 0

    func activate(accountID: UUID?) {
        self.accountID = accountID
        folderSnapshot = nil
        folderRenameNotices = [:]
        updatePending()
    }

    func updateOutbox(_ actions: [PendingAction], revision: Int) {
        guard revision > outboxRevision else { return }
        outboxRevision = revision
        self.actions = actions
        updatePending()
    }

    func updateFolders(_ folders: [LibraryFolder], for userID: UUID?) {
        guard let userID, userID == accountID else { return }
        folderSnapshot = folders
    }

    func reportRename(_ rename: PendingAction.FolderRename, notice: FolderRenameNotice?) {
        guard rename.userID == accountID else { return }
        folderRenameNotices[rename.folderID] = notice
    }

    func clearRenameNotice(for folderID: UUID) { folderRenameNotices[folderID] = nil }

    func retrySync() {
        if isOnline, accountID != nil { requestSync() }
    }

    private func updatePending() {
        guard let accountID else {
            pendingChanges = 0
            pendingFolderIDs = []
            return
        }
        let activeActions = actions.filter { ($0.folderRename?.userID ?? accountID) == accountID }
        pendingChanges = activeActions.count
        pendingFolderIDs = Set(activeActions.compactMap { $0.folderRename?.folderID })
    }
}

nonisolated enum FolderRenameNotice: Equatable, Sendable {
    case nameTaken, folderRemoved, declined

    init(error: any Error) {
        switch error as? APIClientError {
        case .server(status: 409, code: "folder_name_duplicate", detail: _, email: _, retryAfter: _, title: _): self = .nameTaken
        case .server(status: 404, code: _, detail: _, email: _, retryAfter: _, title: _): self = .folderRemoved
        default: self = .declined
        }
    }
}

/// Watches whether the phone has a connection with Apple's `NWPathMonitor`.
///
/// Multithreading: the monitor reports on its own background serial
/// `DispatchQueue` (utility QoS), never blocking the UI; each change is handed
/// back to `DispatchQueue.main` before touching state the screens read.
/// Mirrors `ConnectivityObserver` on Android.
final class ConnectivityMonitor {
    private(set) var isOnline = true
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "centralia.connectivity", qos: .utility)

    init() {
        // The monitor lives as long as the app, so it can hold on to self.
        monitor.pathUpdateHandler = Self.handler { online in
            DispatchQueue.main.async {
                self.update(online)
            }
        }
        monitor.start(queue: queue)
    }

    private func update(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        onChange?(online)
    }

    /// Built outside the main actor: NWPathMonitor calls it on `queue`.
    nonisolated private static func handler(
        _ report: @escaping @Sendable (Bool) -> Void
    ) -> @Sendable (NWPath) -> Void {
        { path in report(path.status == .satisfied) }
    }
}
