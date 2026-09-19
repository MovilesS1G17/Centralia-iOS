import Foundation

struct MockAuthenticationRepository: AuthenticationRepository {
    private let delay: Duration
    private let providerFailures: [AuthenticationProvider: AuthenticationError]

    init(
        delay: Duration = .milliseconds(650),
        providerFailures: [AuthenticationProvider: AuthenticationError] = [:]
    ) {
        self.delay = delay
        self.providerFailures = providerFailures
    }

    func createAccount(email: String, password: String) async throws -> AuthenticatedUser {
        try await simulateWork()

        if email.localizedCaseInsensitiveCompare("existing@example.com") == .orderedSame {
            throw AuthenticationError.accountAlreadyExists
        }

        return AuthenticatedUser(
            id: deterministicID(for: email),
            displayName: displayName(from: email),
            email: email
        )
    }

    func logIn(email: String, password: String) async throws -> AuthenticatedUser {
        try await simulateWork()

        if email.localizedCaseInsensitiveCompare("fail@example.com") == .orderedSame {
            throw AuthenticationError.invalidCredentials
        }

        return AuthenticatedUser(
            id: deterministicID(for: email),
            displayName: displayName(from: email),
            email: email
        )
    }

    func authenticate(with provider: AuthenticationProvider) async throws -> AuthenticatedUser {
        try await simulateWork()

        if let failure = providerFailures[provider] {
            throw failure
        }

        return AuthenticatedUser(
            id: deterministicID(for: provider.rawValue),
            displayName: "Centralia User",
            email: "demo@\(provider.rawValue).example"
        )
    }

    func requestPasswordReset(for email: String) async throws {
        try await simulateWork()

        if email.localizedCaseInsensitiveCompare("reset-fail@example.com") == .orderedSame {
            throw AuthenticationError.resetUnavailable
        }
    }

    func signOut() async throws {
        try await simulateWork()
    }

    private func simulateWork() async throws {
        try await Task.sleep(for: delay)
    }

    private func deterministicID(for value: String) -> UUID {
        var bytes = Array(value.utf8.prefix(16))
        bytes.append(contentsOf: repeatElement(0, count: max(0, 16 - bytes.count)))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func displayName(from email: String) -> String {
        let localPart = email.split(separator: "@").first.map(String.init) ?? "Centralia User"
        let words = localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return words.capitalized
    }
}
