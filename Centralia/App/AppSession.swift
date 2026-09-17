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

    func showSignUp() {
        phase = .unauthenticated(.signUp)
    }

    func showLogIn() {
        phase = .unauthenticated(.logIn)
    }

    func completeAuthentication(with user: AuthenticatedUser) {
        phase = .authenticated(user)
    }
}
