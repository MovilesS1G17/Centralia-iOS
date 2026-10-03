import SwiftUI

struct EmailVerificationView: View {
    @State private var viewModel: EmailVerificationViewModel

    let cancel: () -> Void
    let completeAuthentication: (AuthenticatedUser) -> Void

    init(
        repository: any AuthenticationRepository,
        context: EmailVerificationContext,
        cancel: @escaping () -> Void,
        completeAuthentication: @escaping (AuthenticatedUser) -> Void
    ) {
        // This destination is only created after a V3 registration or login
        // response. Keeping the guard here makes previews and future callers
        // fail safely instead of pretending an older API can verify a code.
        let verificationRepository = repository as? any V3AuthenticationRepository
        _viewModel = State(
            initialValue: EmailVerificationViewModel(
                repository: verificationRepository ?? UnsupportedVerificationRepository(),
                context: context
            )
        )
        self.cancel = cancel
        self.completeAuthentication = completeAuthentication
    }

    var body: some View {
        AuthenticationScaffold {
            VStack(spacing: 0) {
                CentraliaAuthHeader()

                VStack(spacing: CentraliaTheme.Spacing.small) {
                    Text("Verify your email")
                        .font(CentraliaTheme.Typography.display)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("Enter the 6-digit code we sent to \(viewModel.context.email).")
                        .font(.body)
                        .foregroundStyle(Color.centraliaSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 38)

                VStack(spacing: CentraliaTheme.Spacing.medium) {
                    AuthenticationTextField(
                        label: "Verification code",
                        placeholder: "123456",
                        text: $viewModel.code,
                        errorMessage: viewModel.codeError,
                        contentType: .oneTimeCode,
                        keyboardType: .numberPad,
                        submitLabel: .done
                    )
                    .onChange(of: viewModel.code) { _, newValue in
                        let digits = newValue.filter(\.isNumber)
                        if digits != newValue {
                            viewModel.code = String(digits.prefix(6))
                        } else if digits.count > 6 {
                            viewModel.code = String(digits.prefix(6))
                        }
                    }

                    if let failureMessage = viewModel.failureMessage {
                        InlineAuthenticationError(message: failureMessage)
                    }

                    if let resendMessage = viewModel.resendMessage {
                        Text(resendMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.centraliaSecondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    CentraliaPrimaryButton(
                        title: "Verify email",
                        isLoading: viewModel.isVerifying,
                        isDisabled: viewModel.isResending,
                        action: verify
                    )

                    Button(viewModel.isResending ? "Sending code…" : "Resend code") {
                        Task { await viewModel.resendCode() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .disabled(viewModel.isBusy)
                }
                .padding(.top, CentraliaTheme.Spacing.xLarge)
            }
        } footer: {
            Button("Use a different email", action: cancel)
                .font(.subheadline.weight(.semibold))
                .disabled(viewModel.isBusy)
        }
    }

    private func verify() {
        Task {
            if let user = await viewModel.verify() {
                completeAuthentication(user)
            }
        }
    }
}

/// The normal app flow never constructs this repository. It exists so the
/// verification view has a recoverable message if it is accidentally used
/// with a pre-V3 dependency container.
private struct UnsupportedVerificationRepository: V3AuthenticationRepository {
    private let error = AuthenticationError.serverMessage(
        "Email verification is unavailable in this version of the app."
    )

    func createAccount(displayName _: String, email _: String, password _: String) async throws -> AuthenticatedUser { throw error }
    func register(email _: String, password _: String) async throws -> VerificationPending { throw error }
    func verifyEmail(email _: String, code _: String) async throws -> AuthenticatedUser { throw error }
    func resendVerificationCode(email _: String) async throws -> VerificationPending { throw error }
    func logIn(email _: String, password _: String) async throws -> AuthenticatedUser { throw error }
    func confirmPasswordReset(email _: String, code _: String, newPassword _: String) async throws -> AuthenticatedUser { throw error }
    func restoreSession() async throws -> AuthenticatedUser? { throw error }
    func updateDisplayName(_: String, for _: AuthenticatedUser) async throws -> AuthenticatedUser { throw error }
    func authenticate(with _: AuthenticationProvider) async throws -> AuthenticatedUser { throw error }
    func requestPasswordReset(for _: String) async throws { throw error }
    func signOut() async throws { throw error }
}

#Preview {
    EmailVerificationView(
        repository: MockAuthenticationRepository(delay: .zero),
        context: EmailVerificationContext(
            email: "you@example.com",
            resendAvailableIn: 60,
            origin: .registration
        ),
        cancel: {},
        completeAuthentication: { _ in }
    )
}
