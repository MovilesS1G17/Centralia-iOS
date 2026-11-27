import Foundation

/// Eventual connectivity (Sprint 3): what the user sees when something can't
/// be done offline. Same text as `OfflineException` on Android.
nonisolated enum OfflineError: LocalizedError, CodedError, Equatable {
    case needsConnection(String)
    case renameNotStored

    var errorDescription: String? {
        switch self {
        case let .needsConnection(action):
            "You're offline. \(action) needs a connection. Try again when you're back online."
        case .renameNotStored:
            "Centralia couldn’t keep this rename on your device. Try again."
        }
    }

    var code: String { self == .renameNotStored ? "local_storage_unavailable" : "offline" }
}
