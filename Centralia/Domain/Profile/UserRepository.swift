import Foundation

protocol UserRepository {
    func profile(for authenticatedUser: AuthenticatedUser) async throws -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws -> UserProfile
    func changePassword(
        for userID: UUID,
        currentPassword: String,
        newPassword: String
    ) async throws
    func notificationPreferences(for userID: UUID) async throws -> NotificationPreferences
    func updateNotificationPreferences(
        _ preferences: NotificationPreferences,
        for userID: UUID
    ) async throws -> NotificationPreferences
}

enum UserRepositoryError: LocalizedError, Equatable {
    case profileNotFound
    case displayNameRequired
    case invalidEmail
    case incorrectCurrentPassword
    case passwordUnchanged

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            "Your profile could not be found. Please sign in again."
        case .displayNameRequired:
            "Enter your name."
        case .invalidEmail:
            "Enter a valid email address."
        case .incorrectCurrentPassword:
            "The current password is incorrect."
        case .passwordUnchanged:
            "Your new password must be different from the current password."
        }
    }
}

