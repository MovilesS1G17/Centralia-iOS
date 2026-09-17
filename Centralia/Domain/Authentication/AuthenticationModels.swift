import Foundation

struct AuthenticatedUser: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let email: String?
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
    case providerCancelled
    case providerUnavailable
    case resetUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "The email or password is incorrect. Please try again."
        case .accountAlreadyExists:
            "An account already exists for this email. Try logging in instead."
        case .providerCancelled:
            "Sign in was cancelled."
        case .providerUnavailable:
            "This sign-in provider is unavailable right now. Please try again."
        case .resetUnavailable:
            "We could not send a reset link right now. Please try again."
        }
    }
}
