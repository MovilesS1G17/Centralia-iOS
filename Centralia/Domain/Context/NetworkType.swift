import Foundation

/// Context-aware playback: the kind of network the phone is on right now. It is
/// sent to `GET /v1/videos/{id}/playback?network=…`, and the backend decides how
/// to play the short (on mobile data it turns on data saver). Mirrors
/// `NetworkType` in the Android app.
enum NetworkType: String, CaseIterable, Sendable {
    case wifi
    case cellular
    case offline
    case unknown

    /// Pure rule used by the platform reader: Wi-Fi or Ethernet counts as
    /// Wi-Fi even if mobile data is also on; otherwise mobile data is cellular.
    static func from(connected: Bool, wifiOrEthernet: Bool, cellular: Bool) -> NetworkType {
        if !connected { return .offline }
        if wifiOrEthernet { return .wifi }
        if cellular { return .cellular }
        return .unknown
    }
}
