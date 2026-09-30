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
    var displayName = ""
    var email = ""
    var password = ""
    var passwordConfirmation = ""
    var displayNameError: String?
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
                displayName: AuthenticationValidation.normalizedDisplayName(displayName),
                email: AuthenticationValidation.normalizedEmail(email),
                password: password
            )
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
        displayNameError = AuthenticationValidation.displayNameError(for: displayName)
        emailError = AuthenticationValidation.emailError(for: email)
        passwordError = AuthenticationValidation.passwordError(for: password)
        confirmationError = password == passwordConfirmation ? nil : "Passwords do not match."
        return displayNameError == nil
            && emailError == nil
            && passwordError == nil
            && confirmationError == nil
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
        case .displayName:
            displayNameError = message
        case .unknown:
            failureMessage = message
        }
    }
}
