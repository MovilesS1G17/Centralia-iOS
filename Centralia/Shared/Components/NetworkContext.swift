import Foundation
import Network

/// Context-aware playback: reads which network the phone is on right now with
/// Apple's NWPathMonitor (no permission needed). The Android app does the same
/// with ConnectivityManager (`NetworkContext.kt`).
final class NetworkContextMonitor: @unchecked Sendable {
    static let shared = NetworkContextMonitor()

    private let monitor = NWPathMonitor()

    private init() {
        monitor.start(queue: DispatchQueue(label: "centralia.network-context"))
    }

    /// Starts listening early (called at launch) so the first read is accurate.
    func start() {}

    var current: NetworkType {
        let path = monitor.currentPath
        return NetworkType.from(
            connected: path.status == .satisfied,
            wifiOrEthernet: path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet),
            cellular: path.usesInterfaceType(.cellular)
        )
    }
}
