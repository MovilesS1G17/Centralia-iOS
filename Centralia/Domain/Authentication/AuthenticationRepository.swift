import Foundation

protocol AuthenticationRepository {
    func createAccount(email: String, password: String) async throws -> AuthenticatedUser
    func logIn(email: String, password: String) async throws -> AuthenticatedUser
    func authenticate(with provider: AuthenticationProvider) async throws -> AuthenticatedUser
    func requestPasswordReset(for email: String) async throws
    func signOut() async throws
}
