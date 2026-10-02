import Foundation

protocol AuthenticationRepository {
    func createAccount(
        displayName: String,
        email: String,
        password: String
    ) async throws -> AuthenticatedUser
    func logIn(email: String, password: String) async throws -> AuthenticatedUser
    func restoreSession() async throws -> AuthenticatedUser?
    func updateDisplayName(
        _ displayName: String,
        for authenticatedUser: AuthenticatedUser
    ) async throws -> AuthenticatedUser
    func authenticate(with provider: AuthenticationProvider) async throws -> AuthenticatedUser
    func requestPasswordReset(for email: String) async throws
    func signOut() async throws
}

protocol V3AuthenticationRepository: AuthenticationRepository {
    func register(email: String, password: String) async throws -> VerificationPending
    func verifyEmail(email: String, code: String) async throws -> AuthenticatedUser
    func resendVerificationCode(email: String) async throws -> VerificationPending
    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws -> AuthenticatedUser
}
