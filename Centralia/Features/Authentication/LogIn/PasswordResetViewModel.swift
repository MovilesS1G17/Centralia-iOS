import Foundation
import Observation

@Observable
final class PasswordResetViewModel {
    private let repository: any AuthenticationRepository

    var email: String
    var emailError: String?
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
}
