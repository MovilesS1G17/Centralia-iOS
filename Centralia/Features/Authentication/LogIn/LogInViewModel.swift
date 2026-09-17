import Foundation
import Observation

@Observable
final class LogInViewModel {
    private let repository: any AuthenticationRepository

    var email = ""
    var password = ""
    var emailError: String?
    var passwordError: String?
    var failureMessage: String?
    var isSubmittingEmail = false
    var activeProvider: AuthenticationProvider?

    var isBusy: Bool {
        isSubmittingEmail || activeProvider != nil
    }

    init(repository: any AuthenticationRepository) {
        self.repository = repository
    }

    func logIn() async -> AuthenticatedUser? {
        guard !isBusy, validateForm() else {
            return nil
        }

        isSubmittingEmail = true
        failureMessage = nil
        defer { isSubmittingEmail = false }

        do {
            return try await repository.logIn(
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
        passwordError = password.isEmpty ? "Enter your password." : nil
        return emailError == nil && passwordError == nil
    }
}
