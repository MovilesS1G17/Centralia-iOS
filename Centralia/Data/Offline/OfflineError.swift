import Foundation

/// Eventual connectivity (Sprint 3): what the user sees when something can't
/// be done offline. Same text as `OfflineException` on Android.
enum OfflineError: LocalizedError, CodedError, Equatable {
    case needsConnection(String)

    var errorDescription: String? {
        switch self {
        case let .needsConnection(action):
            "You're offline. \(action) needs a connection. Try again when you're back online."
        }
    }

    var code: String { "offline" }
}
