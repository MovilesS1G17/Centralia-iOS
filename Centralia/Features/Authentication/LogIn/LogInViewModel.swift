import Foundation
import Observation

@Observable
final class LogInViewModel {
    private let repository: any AuthenticationRepository
    private let rememberedEmail: any RememberedEmailStoring

    var email = ""
    var password = ""
    var emailError: String?
    var passwordError: String?
    var failureMessage: String?
    var isSubmittingEmail = false
    var activeProvider: AuthenticationProvider?
    /// "Remember my email": kept in the Keychain after a successful sign-in.
    var rememberEmail = true

    var isBusy: Bool {
        isSubmittingEmail || activeProvider != nil
    }

    init(
        repository: any AuthenticationRepository,
        rememberedEmail: any RememberedEmailStoring = InMemoryRememberedEmailStore()
    ) {
        self.repository = repository
        self.rememberedEmail = rememberedEmail
        if let saved = rememberedEmail.email(), !saved.isEmpty {
            email = saved
        }
    }

    func logIn() async -> LogInOutcome? {
        guard !isBusy, validateForm() else {
            return nil
        }

        isSubmittingEmail = true
        failureMessage = nil
        defer { isSubmittingEmail = false }

        do {
            let normalizedEmail = AuthenticationValidation.normalizedEmail(email)
            let user = try await repository.logIn(email: normalizedEmail, password: password)
            if rememberEmail {
                rememberedEmail.remember(normalizedEmail)
            } else {
                rememberedEmail.forget()
            }
            return .authenticated(user)
        } catch is CancellationError {
            return nil
        } catch let AuthenticationError.verificationRequired(email, resendAvailableIn) {
            return .emailVerification(
                EmailVerificationContext(
                    email: email.isEmpty ? AuthenticationValidation.normalizedEmail(self.email) : email,
                    resendAvailableIn: resendAvailableIn,
                    origin: .signIn
                )
            )
        } catch let error as AuthenticationError {
            present(error)
            return nil
        } catch {
            failureMessage = error.localizedDescription
            return nil
        }
    }

    func authenticate(with provider: AuthenticationProvider) async -> AuthenticatedUser? {
        guard !isBusy else { return nil }

        activeProvider = provider
        failureMessage = nil
        defer { activeProvider = nil }

        do {
            return try await repository.authenticate(with: provider)
        } catch is CancellationError {
            return nil
        } catch let error as AuthenticationError {
            present(error)
            return nil
        } catch {
            failureMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    private func validateForm() -> Bool {
        emailError = AuthenticationValidation.emailError(for: email)
        passwordError = password.isEmpty ? "Enter your password." : nil
        return emailError == nil && passwordError == nil
    }

    private func present(_ error: AuthenticationError) {
        guard case let .validation(field, message) = error else {
            failureMessage = error.localizedDescription
            return
        }

        switch field {
        case .email:
            emailError = message
        case .password:
            passwordError = message
        case .displayName, .unknown:
            failureMessage = message
        }
    }
}
