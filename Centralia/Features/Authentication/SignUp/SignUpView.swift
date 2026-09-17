import SwiftUI

struct SignUpView: View {
    @State private var viewModel: SignUpViewModel
    @State private var presentedLegalDocument: LegalDocument?

    let showLogIn: () -> Void
    let completeAuthentication: (AuthenticatedUser) -> Void

    init(
        repository: any AuthenticationRepository,
        showLogIn: @escaping () -> Void,
        completeAuthentication: @escaping (AuthenticatedUser) -> Void
    ) {
        _viewModel = State(initialValue: SignUpViewModel(repository: repository))
        self.showLogIn = showLogIn
        self.completeAuthentication = completeAuthentication
    }

    var body: some View {
        AuthenticationScaffold {
            VStack(spacing: 0) {
                CentraliaAuthHeader()

                VStack(spacing: CentraliaTheme.Spacing.small) {
                    Text("Save every short worth keeping.")
                        .font(CentraliaTheme.Typography.display)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Text("TikToks, Reels, and Shorts together.")
                        .font(.body)
                        .foregroundStyle(Color.centraliaSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 38)

                Group {
                    switch viewModel.mode {
                    case .options:
                        optionControls
                    case .email:
                        emailControls
                    }
                }
                .padding(.top, CentraliaTheme.Spacing.xLarge)
            }
        } footer: {
            VStack(spacing: CentraliaTheme.Spacing.medium) {
                HStack(spacing: 5) {
                    Text("Already have an account?")
                        .foregroundStyle(Color.centraliaSecondaryText)

                    Button("Log In", action: showLogIn)
                        .fontWeight(.semibold)
                        .disabled(viewModel.isBusy)
                }
                .font(.subheadline)

                LegalAgreementText { document in
                    presentedLegalDocument = document
                }
            }
        }
        .sheet(item: $presentedLegalDocument) { document in
            LegalDocumentSheet(document: document)
        }
    }

    @ViewBuilder
    private var optionControls: some View {
        VStack(spacing: CentraliaTheme.Spacing.medium) {
            CentraliaSecondaryButton(
                title: "Continue with Apple",
                isDisabled: viewModel.isBusy,
                icon: {
                    providerIcon(for: .apple)
                },
                action: {
                    authenticate(with: .apple)
                }
            )

            CentraliaSecondaryButton(
                title: "Continue with Google",
                isDisabled: viewModel.isBusy,
                icon: {
                    providerIcon(for: .google)
                },
                action: {
                    authenticate(with: .google)
                }
            )

            AuthenticationDivider(text: "or")
                .padding(.vertical, CentraliaTheme.Spacing.xSmall)

            CentraliaPrimaryButton(
                title: "Continue with email",
                isDisabled: viewModel.isBusy,
                action: viewModel.showEmailForm
            )

            if let failureMessage = viewModel.failureMessage {
                InlineAuthenticationError(message: failureMessage)
            }
        }
    }

    @ViewBuilder
    private var emailControls: some View {
        VStack(spacing: CentraliaTheme.Spacing.medium) {
            AuthenticationTextField(
                label: "Email",
                placeholder: "you@example.com",
                text: $viewModel.email,
                errorMessage: viewModel.emailError,
                contentType: .emailAddress,
                keyboardType: .emailAddress
            )

            AuthenticationTextField(
                label: "Password",
                placeholder: "At least 8 characters",
                text: $viewModel.password,
                errorMessage: viewModel.passwordError,
                contentType: .newPassword,
                isSecure: true
            )

            AuthenticationTextField(
                label: "Confirm password",
                placeholder: "Repeat your password",
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
                title: "Create account",
                isLoading: viewModel.isSubmittingEmail,
                action: createAccount
            )

            Button("Use another method", action: viewModel.showOptions)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .disabled(viewModel.isBusy)
        }
    }

    @ViewBuilder
    private func providerIcon(for provider: AuthenticationProvider) -> some View {
        if viewModel.activeProvider == provider {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading")
        } else if provider == .apple {
            Image(systemName: "apple.logo")
                .font(.system(size: 21, weight: .medium))
                .accessibilityHidden(true)
        } else {
            GoogleMark()
        }
    }

    private func createAccount() {
        Task {
            if let user = await viewModel.createAccount() {
                completeAuthentication(user)
            }
        }
    }

    private func authenticate(with provider: AuthenticationProvider) {
        Task {
            if let user = await viewModel.authenticate(with: provider) {
                completeAuthentication(user)
            }
        }
    }
}

#Preview {
    SignUpView(
        repository: MockAuthenticationRepository(delay: .zero),
        showLogIn: {},
        completeAuthentication: { _ in }
    )
}
