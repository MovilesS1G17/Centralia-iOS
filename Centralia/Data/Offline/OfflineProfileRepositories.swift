import Foundation

/// Eventual connectivity + local storage (Sprint 3) for search history:
/// network falling back to the copy in `UserDefaults`. A search made offline is
/// recorded locally right away. Mirrors `OfflineSearchHistoryRepository`.
final class OfflineSearchHistoryRepository: SearchHistoryRepository {
    private let remote: any SearchHistoryRepository
    private let defaults: UserDefaults
    private static let key = "recentSearches"
    private static let limit = 8

    init(remote: any SearchHistoryRepository, defaults: UserDefaults) {
        self.remote = remote
        self.defaults = defaults
    }

    func recentSearches() async throws -> [String] {
        do {
            let fresh = try await remote.recentSearches()
            save(fresh)
            return fresh
        } catch where APIClientError.isOffline(error) {
            return load()
        }
    }

    func recordSearch(_ query: String) async throws {
        save(Array(([query] + load().filter { $0.caseInsensitiveCompare(query) != .orderedSame }).prefix(Self.limit)))
        do {
            try await remote.recordSearch(query)
        } catch where APIClientError.isOffline(error) {
            // Kept locally.
        }
    }

    func clearSearchHistory() async throws {
        save([])
        do {
            try await remote.clearSearchHistory()
        } catch where APIClientError.isOffline(error) {
            // Cleared locally.
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private func save(_ searches: [String]) {
        defaults.set(searches, forKey: Self.key)
    }

    private func load() -> [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }
}

/// Eventual connectivity + local storage (Sprint 3) for the profile: network
/// falling back to the last copy (JSON in `UserDefaults`); changes need a
/// connection. Mirrors `OfflineUserRepository` on Android.
final class OfflineUserRepository: UserRepository {
    private let remote: any UserRepository
    private let defaults: UserDefaults
    private static let profileKey = "profile"
    private static let notificationsKey = "notificationPreferences"

    init(remote: any UserRepository, defaults: UserDefaults) {
        self.remote = remote
        self.defaults = defaults
    }

    func profile(for authenticatedUser: AuthenticatedUser) async throws -> UserProfile {
        do {
            let fresh = try await remote.profile(for: authenticatedUser)
            store(fresh, forKey: Self.profileKey)
            return fresh
        } catch where APIClientError.isOffline(error) {
            guard let saved: UserProfile = load(forKey: Self.profileKey) else {
                throw OfflineError.needsConnection("Loading your profile for the first time")
            }
            return saved
        }
    }

    func notificationPreferences(for userID: UUID) async throws -> NotificationPreferences {
        do {
            let fresh = try await remote.notificationPreferences(for: userID)
            store(fresh, forKey: Self.notificationsKey)
            return fresh
        } catch where APIClientError.isOffline(error) {
            return load(forKey: Self.notificationsKey) ?? .defaults
        }
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        try await networkOnly("Changing your profile") { try await remote.updateProfile(profile) }
    }

    func changePassword(for userID: UUID, currentPassword: String, newPassword: String) async throws {
        try await networkOnly("Changing your password") {
            try await remote.changePassword(for: userID, currentPassword: currentPassword, newPassword: newPassword)
        }
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences,
        for userID: UUID
    ) async throws -> NotificationPreferences {
        try await networkOnly("Changing notifications") {
            try await remote.updateNotificationPreferences(preferences, for: userID)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.profileKey)
        defaults.removeObject(forKey: Self.notificationsKey)
    }

    private func store<Value: Encodable>(_ value: Value, forKey key: String) {
        if let data = try? OfflineJSON.encoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private func load<Value: Decodable>(forKey key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? OfflineJSON.decoder().decode(Value.self, from: $0) }
    }

    private func networkOnly<T>(_ action: String, send: () async throws -> T) async throws -> T {
        do {
            return try await send()
        } catch where APIClientError.isOffline(error) {
            throw OfflineError.needsConnection(action)
        }
    }
}
