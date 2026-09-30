import Observation

@Observable
final class AppSession {
    enum Phase: Equatable {
        case unauthenticated(AuthenticationDestination)
        case authenticated(AuthenticatedUser)
    }

    enum AuthenticationDestination: Equatable {
        case signUp
        case logIn
    }

    var phase: Phase = .unauthenticated(.signUp)
    private(set) var isRestoringSession: Bool

    init(isRestoringSession: Bool = false) {
        self.isRestoringSession = isRestoringSession
    }

    func showSignUp() {
        phase = .unauthenticated(.signUp)
    }

    func showLogIn() {
        phase = .unauthenticated(.logIn)
    }

    func completeAuthentication(with user: AuthenticatedUser) {
        phase = .authenticated(user)
    }

    func updateAuthenticatedUser(_ user: AuthenticatedUser) {
        guard case .authenticated = phase else { return }
        phase = .authenticated(user)
    }

    func signOut() {
        phase = .unauthenticated(.logIn)
    }

    func restoreAuthentication(using repository: any AuthenticationRepository) async {
        guard isRestoringSession else { return }
        defer { isRestoringSession = false }

        do {
            if let user = try await repository.restoreSession() {
                completeAuthentication(with: user)
            }
        } catch {
            // A transient network failure should not erase a valid Keychain token.
            // The person can still log in again from the authentication screen.
        }
    }
}
