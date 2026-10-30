import Foundation
import Network
import Observation

/// Eventual connectivity (Sprint 3): what the offline banner shows, read by
/// the screens on the main thread.
@Observable
final class OfflineStatus {
    var isOnline = true
    var pendingChanges = 0
    /// Goes up every time queued changes reach the server, so the lists reload.
    var syncRevision = 0
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
