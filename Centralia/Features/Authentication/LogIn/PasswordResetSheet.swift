import SwiftUI

struct PasswordResetSheet: View {
    @State private var viewModel: PasswordResetViewModel
    @Environment(\.dismiss) private var dismiss

    init(repository: any AuthenticationRepository, initialEmail: String) {
        _viewModel = State(
            initialValue: PasswordResetViewModel(
                repository: repository,
                initialEmail: initialEmail
            )
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                if viewModel.didSend {
                    ContentUnavailableView {
                        Label("Check your email", systemImage: "envelope.badge")
                    } description: {
                        Text("A mock reset link was sent to \(AuthenticationValidation.normalizedEmail(viewModel.email)).")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        title: "Send reset link",
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
                    Button(viewModel.didSend ? "Done" : "Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
