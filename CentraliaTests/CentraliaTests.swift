import Foundation
import Testing
@testable import Centralia

struct CentraliaTests {
    @Test func authenticationValidation() {
        #expect(AuthenticationValidation.emailError(for: "person@example.com") == nil)
        #expect(AuthenticationValidation.emailError(for: "not-an-email") != nil)
        #expect(AuthenticationValidation.passwordError(for: "12345678") == nil)
        #expect(AuthenticationValidation.passwordError(for: "short") != nil)
    }

    @Test func signUpRejectsMismatchedPasswordsBeforeCallingRepository() async {
        let viewModel = SignUpViewModel(
            repository: MockAuthenticationRepository(delay: .zero)
        )
        viewModel.email = "person@example.com"
        viewModel.password = "password-one"
        viewModel.passwordConfirmation = "password-two"

        let user = await viewModel.createAccount()

        #expect(user == nil)
        #expect(viewModel.confirmationError == "Passwords do not match.")
        #expect(viewModel.isSubmittingEmail == false)
    }

    @Test func logInPreservesInputAndExposesRecoverableFailure() async {
        let viewModel = LogInViewModel(
            repository: MockAuthenticationRepository(delay: .zero)
        )
        viewModel.email = "fail@example.com"
        viewModel.password = "valid-password"

        let user = await viewModel.logIn()

        #expect(user == nil)
        #expect(viewModel.email == "fail@example.com")
        #expect(viewModel.password == "valid-password")
        #expect(viewModel.failureMessage == AuthenticationError.invalidCredentials.localizedDescription)
    }

    @Test func socialAuthenticationCompletesSession() async throws {
        let repository = MockAuthenticationRepository(delay: .zero)
        let session = AppSession()

        let user = try await repository.authenticate(with: .apple)
        session.completeAuthentication(with: user)

        #expect(session.phase == .authenticated(user))
    }

    @Test func socialAuthenticationCancellationIsRecoverable() async {
        let viewModel = SignUpViewModel(
            repository: MockAuthenticationRepository(
                delay: .zero,
                providerFailures: [.apple: .providerCancelled]
            )
        )

        let user = await viewModel.authenticate(with: .apple)

        #expect(user == nil)
        #expect(viewModel.failureMessage == AuthenticationError.providerCancelled.localizedDescription)
        #expect(viewModel.activeProvider == nil)
    }

    @Test func deterministicMockReturnsSameIdentityForSameEmail() async throws {
        let repository = MockAuthenticationRepository(delay: .zero)

        let first = try await repository.logIn(
            email: "person@example.com",
            password: "valid-password"
        )
        let second = try await repository.logIn(
            email: "person@example.com",
            password: "another-password"
        )

        #expect(first.id == second.id)
    }
}
