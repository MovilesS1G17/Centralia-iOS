import Foundation

/// Which URLs the players may load. Playback is https only; debug builds also
/// accept plain http for local-network hosts so a development backend works.
enum PlaybackURLPolicy {
    static var allowsLocalHTTP: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func isAllowed(_ url: URL, allowLocalHTTP: Bool = allowsLocalHTTP) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }

        switch url.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            return allowLocalHTTP && isLocalHost(host)
        default:
            return false
        }
    }

    static func isLocalHost(_ host: String) -> Bool {
        let value = host.lowercased()
        if value == "localhost" || value == "::1" || value.hasSuffix(".local") {
            return true
        }

        let parts = value.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }

        switch (parts[0], parts[1]) {
        case (127, _), (10, _), (192, 168), (169, 254):
            return true
        case (172, 16...31):
            return true
        default:
            return false
        }
    }
}
