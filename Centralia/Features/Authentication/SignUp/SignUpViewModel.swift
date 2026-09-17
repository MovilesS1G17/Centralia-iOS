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

    func createAccount() async -> AuthenticatedUser? {
        guard !isBusy, validateForm() else {
            return nil
        }

        isSubmittingEmail = true
        failureMessage = nil
        defer { isSubmittingEmail = false }

        do {
            return try await repository.createAccount(
                email: AuthenticationValidation.normalizedEmail(email),
                password: password
            )
        } catch is CancellationError {
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
}
