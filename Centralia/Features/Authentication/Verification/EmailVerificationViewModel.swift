import Foundation
import Observation

@Observable
final class EmailVerificationViewModel {
    private let repository: any V3AuthenticationRepository
    let context: EmailVerificationContext

    var code = ""
    var codeError: String?
    var failureMessage: String?
    var resendMessage: String?
    var isVerifying = false
    var isResending = false

    var isBusy: Bool {
        isVerifying || isResending
    }

    init(repository: any V3AuthenticationRepository, context: EmailVerificationContext) {
        self.repository = repository
        self.context = context
    }

    func verify() async -> AuthenticatedUser? {
        guard !isBusy else { return nil }

        code = code.filter(\.isNumber)
        codeError = code.count == 6 ? nil : "Enter the 6-digit code from your email."
        guard codeError == nil else { return nil }

        isVerifying = true
        failureMessage = nil
        defer { isVerifying = false }

        do {
            let verifiedUser = try await repository.verifyEmail(email: context.email, code: code)
            guard let intendedDisplayName = context.intendedDisplayName,
                  AuthenticationValidation.displayNameError(for: intendedDisplayName) == nil,
                  intendedDisplayName != verifiedUser.displayName else {
                return verifiedUser
            }

            return try await repository.updateDisplayName(
                intendedDisplayName,
                for: verifiedUser
            )
        } catch is CancellationError {
            return nil
        } catch let error as AuthenticationError {
            failureMessage = error.localizedDescription
            return nil
        } catch {
            failureMessage = error.localizedDescription
            return nil
        }
    }

    func resendCode() async {
        guard !isBusy else { return }

        isResending = true
        failureMessage = nil
        resendMessage = nil
        defer { isResending = false }

        do {
            let pending = try await repository.resendVerificationCode(email: context.email)
            resendMessage = "A new code was sent. It may take a moment to arrive."
            if pending.resendAvailableIn > 0 {
                resendMessage = "A new code was sent. You can request another one in \(pending.resendAvailableIn) seconds."
            }
        } catch is CancellationError {
            return
        } catch let error as AuthenticationError {
            failureMessage = error.localizedDescription
        } catch {
            failureMessage = error.localizedDescription
        }
    }
}
