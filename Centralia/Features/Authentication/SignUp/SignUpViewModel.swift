import Foundation
import Observation

@Observable
final class SignUpViewModel {
    enum Mode {
        case options
        case email
    }

    private let repository: any AuthenticationRepository

    var mode: Mode = .options
    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var emailError: String?
    var passwordError: String?
    var confirmationError: String?
    var failureMessage: String?
    var isSubmittingEmail = false
    var activeProvider: AuthenticationProvider?

    var isBusy: Bool {
        isSubmittingEmail || activeProvider != nil
    }

    init(repository: any AuthenticationRepository) {
        self.repository = repository
    }

    func showEmailForm() {
        failureMessage = nil
        mode = .email
    }

    func showOptions() {
        failureMessage = nil
        mode = .options
    }

    func createAccount() async -> SignUpOutcome? {
        guard !isBusy, validateForm() else {
            return nil
        }

        isSubmittingEmail = true
        failureMessage = nil
        defer { isSubmittingEmail = false }

        do {
            let normalizedEmail = AuthenticationValidation.normalizedEmail(email)

            if let repository = repository as? any V3AuthenticationRepository {
                let pending = try await repository.register(
                    email: normalizedEmail,
                    password: password
                )
                return .emailVerification(
                    EmailVerificationContext(
                        email: pending.email,
                        resendAvailableIn: pending.resendAvailableIn,
                        origin: .registration
                    )
                )
            }

            // The production container always supplies a V3 repository. This
            // fallback only keeps the legacy mock boundary recoverable.
            let user = try await repository.createAccount(
                displayName: normalizedEmail,
                email: normalizedEmail,
                password: password
            )
            return .authenticated(user)
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
        passwordError = AuthenticationValidation.passwordError(for: password)
        confirmationError = password == passwordConfirmation ? nil : "Passwords do not match."
        return emailError == nil && passwordError == nil && confirmationError == nil
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
