import SwiftUI

struct PasswordResetSheet: View {
    @State private var viewModel: PasswordResetViewModel
    @Environment(\.dismiss) private var dismiss
    let completeAuthentication: (AuthenticatedUser) -> Void

    init(
        repository: any AuthenticationRepository,
        initialEmail: String,
        completeAuthentication: @escaping (AuthenticatedUser) -> Void
    ) {
        _viewModel = State(
            initialValue: PasswordResetViewModel(
                repository: repository,
                initialEmail: initialEmail
            )
        )
        self.completeAuthentication = completeAuthentication
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                if viewModel.didSend {
                    confirmationForm
                } else {
                    VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
                        Text("Reset your password")
                            .font(CentraliaTheme.Typography.display)
                            .accessibilityAddTraits(.isHeader)

                        Text("Enter the email associated with your Centralia account.")
                            .foregroundStyle(Color.centraliaSecondaryText)
                    }

                    AuthenticationTextField(
                        label: "Email",
                        placeholder: "you@example.com",
                        text: $viewModel.email,
                        errorMessage: viewModel.emailError,
                        contentType: .emailAddress,
                        keyboardType: .emailAddress,
                        submitLabel: .done
                    )

                    if let failureMessage = viewModel.failureMessage {
                        InlineAuthenticationError(message: failureMessage)
                    }

                    CentraliaPrimaryButton(
                        title: "Send reset code",
                        isLoading: viewModel.isSubmitting
                    ) {
                        Task {
                            await viewModel.sendReset()
                        }
                    }

                    Spacer()
                }
            }
            .padding(CentraliaTheme.Spacing.large)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .navigationTitle("Password reset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var confirmationForm: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
                Text("Check your email")
                    .font(CentraliaTheme.Typography.display)
                    .accessibilityAddTraits(.isHeader)

                Text("Enter the 6-digit code sent to \(AuthenticationValidation.normalizedEmail(viewModel.email)), then choose a new password.")
                    .foregroundStyle(Color.centraliaSecondaryText)
            }

            AuthenticationTextField(
                label: "Verification code",
                placeholder: "123456",
                text: $viewModel.code,
                errorMessage: viewModel.codeError,
                contentType: .oneTimeCode,
                keyboardType: .numberPad
            )
            .onChange(of: viewModel.code) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                viewModel.code = String(digits.prefix(6))
            }

            AuthenticationTextField(
                label: "New password",
                placeholder: "At least 8 characters",
                text: $viewModel.newPassword,
                errorMessage: viewModel.newPasswordError,
                contentType: .newPassword,
                isSecure: true
            )

            AuthenticationTextField(
                label: "Confirm new password",
                placeholder: "Repeat your new password",
                text: $viewModel.passwordConfirmation,
                errorMessage: viewModel.confirmationError,
                contentType: .newPassword,
                isSecure: true,
                submitLabel: .done
            )

            if let failureMessage = viewModel.failureMessage {
                InlineAuthenticationError(message: failureMessage)
            }

            CentraliaPrimaryButton(
                title: "Reset password",
                isLoading: viewModel.isSubmitting,
                action: confirmReset
            )

            Button("Use a different email") {
                viewModel.didSend = false
                viewModel.failureMessage = nil
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .disabled(viewModel.isSubmitting)

            Spacer()
        }
    }

    private func confirmReset() {
        Task {
            if let user = await viewModel.confirmReset() {
                completeAuthentication(user)
                dismiss()
            }
        }
    }
}
