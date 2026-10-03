import Foundation
import Observation

@Observable
final class PasswordResetViewModel {
    private let repository: any AuthenticationRepository

    var email: String
    var code = ""
    var newPassword = ""
    var passwordConfirmation = ""
    var emailError: String?
    var codeError: String?
    var newPasswordError: String?
    var confirmationError: String?
    var failureMessage: String?
    var isSubmitting = false
    var didSend = false

    init(repository: any AuthenticationRepository, initialEmail: String) {
        self.repository = repository
        email = initialEmail
    }

    func sendReset() async {
        guard !isSubmitting else { return }

        emailError = AuthenticationValidation.emailError(for: email)
        guard emailError == nil else { return }

        isSubmitting = true
        failureMessage = nil
        defer { isSubmitting = false }

        do {
            try await repository.requestPasswordReset(
                for: AuthenticationValidation.normalizedEmail(email)
            )
            didSend = true
        } catch is CancellationError {
            return
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    func confirmReset() async -> AuthenticatedUser? {
        guard !isSubmitting else { return nil }

        let normalizedEmail = AuthenticationValidation.normalizedEmail(email)
        code = code.filter(\.isNumber)
        codeError = code.count == 6 ? nil : "Enter the 6-digit code from your email."
        newPasswordError = AuthenticationValidation.passwordError(for: newPassword)
        confirmationError = newPassword == passwordConfirmation ? nil : "Passwords do not match."
        guard codeError == nil, newPasswordError == nil, confirmationError == nil else {
            return nil
        }
        guard let repository = repository as? any V3AuthenticationRepository else {
            failureMessage = "Password reset is unavailable in this version of the app."
            return nil
        }

        isSubmitting = true
        failureMessage = nil
        defer { isSubmitting = false }

        do {
            return try await repository.confirmPasswordReset(
                email: normalizedEmail,
                code: code,
                newPassword: newPassword
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

    private func present(_ error: AuthenticationError) {
        guard case let .validation(field, message) = error else {
            failureMessage = error.localizedDescription
            return
        }

        switch field {
        case .email:
            emailError = message
        case .password:
            newPasswordError = message
        case .displayName, .unknown:
            failureMessage = message
        }
    }
}
