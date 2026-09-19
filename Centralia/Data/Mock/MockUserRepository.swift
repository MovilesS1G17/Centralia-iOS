import Foundation

actor MockUserRepository: UserRepository {
    private struct UserRecord: Codable, Sendable {
        var profile: UserProfile
        var notificationPreferences: NotificationPreferences
    }

    private struct Snapshot: Codable, Sendable {
        let schemaVersion: Int
        var records: [UserRecord]
    }

    private let store: MockDataStore
    private let filename: String
    private let delay: Duration

    init(
        store: MockDataStore = MockDataStore(),
        filename: String = "users-v1.json",
        delay: Duration = .milliseconds(280)
    ) {
        self.store = store
        self.filename = filename
        self.delay = delay
    }

    func profile(for authenticatedUser: AuthenticatedUser) async throws -> UserProfile {
        try await simulateWork()
        var value = try await snapshot()

        if let record = value.records.first(where: { $0.profile.id == authenticatedUser.id }) {
            return record.profile
        }

        let profile = UserProfile(
            id: authenticatedUser.id,
            displayName: authenticatedUser.displayName,
            email: authenticatedUser.email ?? "",
            membershipStatus: .centraliaMember
        )
        value.records.append(
            UserRecord(profile: profile, notificationPreferences: .defaults)
        )
        try await store.save(value, to: filename)
        return profile
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        try await simulateWork()
        let normalizedName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = AuthenticationValidation.normalizedEmail(profile.email)

        guard !normalizedName.isEmpty else {
            throw UserRepositoryError.displayNameRequired
        }
        guard AuthenticationValidation.emailError(for: normalizedEmail) == nil else {
            throw UserRepositoryError.invalidEmail
        }

        var value = try await snapshot()
        guard let index = value.records.firstIndex(where: { $0.profile.id == profile.id }) else {
            throw UserRepositoryError.profileNotFound
        }

        value.records[index].profile.displayName = normalizedName
        value.records[index].profile.email = normalizedEmail
        let updatedProfile = value.records[index].profile
        try await store.save(value, to: filename)
        return updatedProfile
    }

    func changePassword(
        for userID: UUID,
        currentPassword: String,
        newPassword: String
    ) async throws {
        try await simulateWork()
        let value = try await snapshot()
        guard value.records.contains(where: { $0.profile.id == userID }) else {
            throw UserRepositoryError.profileNotFound
        }
        guard currentPassword != "wrong-password" else {
            throw UserRepositoryError.incorrectCurrentPassword
        }
        guard currentPassword != newPassword else {
            throw UserRepositoryError.passwordUnchanged
        }
    }

    func notificationPreferences(for userID: UUID) async throws -> NotificationPreferences {
        try await simulateWork()
        let value = try await snapshot()
        guard let record = value.records.first(where: { $0.profile.id == userID }) else {
            throw UserRepositoryError.profileNotFound
        }
        return record.notificationPreferences
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences,
        for userID: UUID
    ) async throws -> NotificationPreferences {
        try await simulateWork()
        var value = try await snapshot()
        guard let index = value.records.firstIndex(where: { $0.profile.id == userID }) else {
            throw UserRepositoryError.profileNotFound
        }
        value.records[index].notificationPreferences = preferences
        try await store.save(value, to: filename)
        return preferences
    }

    private func snapshot() async throws -> Snapshot {
        try await store.load(
            Snapshot.self,
            from: filename,
            seed: Snapshot(schemaVersion: 1, records: [])
        )
    }

    private func simulateWork() async throws {
        try await Task.sleep(for: delay)
    }
}

