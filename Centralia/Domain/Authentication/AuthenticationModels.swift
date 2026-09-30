import Foundation

struct AuthenticatedUser: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let email: String?
}

enum AuthenticationField: String, Equatable, Sendable {
    case email
    case password
    case displayName = "display_name"
    case unknown
}

enum AuthenticationProvider: String, CaseIterable, Sendable {
    case apple
    case google

    var displayName: String {
        rawValue.capitalized
    }
}

enum AuthenticationError: LocalizedError, Equatable {
    case invalidCredentials
    case accountAlreadyExists
    case validation(field: AuthenticationField, message: String)
    case providerCancelled
    case providerUnavailable
    case resetUnavailable
    case networkUnavailable
    case sessionExpired
    case secureStorageUnavailable
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password is incorrect. Please try again."
        case .accountAlreadyExists:
            "An account already exists for this email. Try logging in instead."
        case let .validation(_, message):
            message
        case .providerCancelled:
            "Sign in was cancelled."
        case .providerUnavailable:
            "This sign-in provider is unavailable right now. Please try again."
        case .resetUnavailable:
            "We could not send a reset link right now. Please try again."
        case .networkUnavailable:
            "We couldn’t reach Centralia right now. Check your connection and try again."
        case .sessionExpired:
            "Your session has expired. Please log in again."
        case .secureStorageUnavailable:
            "We couldn’t securely save your session. Please try again."
        case .requestFailed:
            "We couldn’t complete that request. Please try again."
        }
    }
}
