import Foundation

private struct ProfileUpdateBody: Encodable {
    let displayName: String
    let email: String
}

private struct PasswordChangeBody: Encodable {
    let currentPassword: String
    let newPassword: String
}

private struct SearchBody: Encodable {
    let query: String
}

struct APIUserRepository: UserRepository {
    let client: APIClient

    func profile(for _: AuthenticatedUser) async throws -> UserProfile {
        try await client.request(UserProfileDTO.self, path: "/v1/me").model
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        let body = try client.encode(ProfileUpdateBody(displayName: profile.displayName, email: profile.email))
        return try await client.request(UserProfileDTO.self, path: "/v1/me", method: "PATCH", body: body).model
    }

    func changePassword(for _: UUID, currentPassword: String, newPassword: String) async throws {
        let body = try client.encode(PasswordChangeBody(currentPassword: currentPassword, newPassword: newPassword))
        _ = try await client.send("/v1/me/password", method: "POST", body: body)
    }

    func notificationPreferences(for _: UUID) async throws -> NotificationPreferences {
        try await client.request(NotificationPreferences.self, path: "/v1/me/notification-preferences")
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences, for _: UUID
    ) async throws -> NotificationPreferences {
        let body = try client.encode(preferences)
        return try await client.request(
            NotificationPreferences.self, path: "/v1/me/notification-preferences", method: "PUT", body: body
        )
    }
}

struct APISearchHistoryRepository: SearchHistoryRepository {
    let client: APIClient

    func recentSearches() async throws -> [String] {
        try await client.request([String].self, path: "/v1/search-history")
    }

    func recordSearch(_ query: String) async throws {
        let body = try client.encode(SearchBody(query: query))
        _ = try await client.send("/v1/search-history", method: "POST", body: body)
    }

    func clearSearchHistory() async throws {
        _ = try await client.send("/v1/search-history", method: "DELETE")
    }
}
