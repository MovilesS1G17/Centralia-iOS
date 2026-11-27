import SwiftUI

struct LogInView: View {
    @State private var viewModel: LogInViewModel
    @State private var showsPasswordReset = false

    private let repository: any AuthenticationRepository
    let showSignUp: () -> Void
    let showEmailVerification: (EmailVerificationContext) -> Void
    let completeAuthentication: (AuthenticatedUser) -> Void

    init(
        repository: any AuthenticationRepository,
        rememberedEmail: any RememberedEmailStoring = InMemoryRememberedEmailStore(),
        showSignUp: @escaping () -> Void,
        showEmailVerification: @escaping (EmailVerificationContext) -> Void,
        completeAuthentication: @escaping (AuthenticatedUser) -> Void
    ) {
        self.repository = repository
        _viewModel = State(
            initialValue: LogInViewModel(repository: repository, rememberedEmail: rememberedEmail)
        )
        self.showSignUp = showSignUp
        self.showEmailVerification = showEmailVerification
        self.completeAuthentication = completeAuthentication
    }

    var body: some View {
        AuthenticationScaffold {
            VStack(spacing: 0) {
                CentraliaAuthHeader()

                VStack(spacing: CentraliaTheme.Spacing.small) {
                    Text("Welcome back.")
                        .font(CentraliaTheme.Typography.display)
                        .accessibilityAddTraits(.isHeader)

                    Text("Your short-video library is ready.")
                        .font(.body)
                        .foregroundStyle(Color.centraliaSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

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
                        placeholder: "Enter your password",
                        text: $viewModel.password,
                        errorMessage: viewModel.passwordError,
                        contentType: .password,
                        isSecure: true,
                        submitLabel: .done
                    )

                    HStack {
                        Button {
                            viewModel.rememberEmail.toggle()
                        } label: {
                            Label(
                                "Remember my email",
                                systemImage: viewModel.rememberEmail ? "checkmark.square.fill" : "square"
                            )
                            .font(.subheadline)
                        }
                        .foregroundStyle(Color.centraliaInk)
                        .accessibilityValue(viewModel.rememberEmail ? "On" : "Off")
                        .accessibilityIdentifier("rememberEmailToggle")
                        .disabled(viewModel.isBusy)

                        Spacer()

                        Button("Forgot password?") {
                            showsPasswordReset = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .disabled(viewModel.isBusy)
                    }
                    .frame(minHeight: 44)

                    if let failureMessage = viewModel.failureMessage {
                        InlineAuthenticationError(message: failureMessage)
                    }

                    CentraliaPrimaryButton(
                        title: "Log In",
                        isLoading: viewModel.isSubmittingEmail,
                        action: logIn
                    )

                    AuthenticationDivider(text: "or continue with")
                        .padding(.vertical, CentraliaTheme.Spacing.xSmall)

                    HStack(spacing: CentraliaTheme.Spacing.medium) {
                        socialButton(for: .apple)
                        socialButton(for: .google)
                    }
                }
                .padding(.top, CentraliaTheme.Spacing.xLarge)
            }
        } footer: {
            HStack(spacing: 5) {
                Text("New to Centralia?")
                    .foregroundStyle(Color.centraliaSecondaryText)

                Button("Create account", action: showSignUp)
                    .fontWeight(.semibold)
                    .disabled(viewModel.isBusy)
            }
            .font(.subheadline)
        }
        .sheet(isPresented: $showsPasswordReset) {
            PasswordResetSheet(
                repository: repository,
                initialEmail: viewModel.email,
                completeAuthentication: completeAuthentication
            )
        }
    }

    private func socialButton(for provider: AuthenticationProvider) -> some View {
        CentraliaSecondaryButton(
            title: provider.displayName,
            isDisabled: viewModel.isBusy,
            icon: {
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
            },
            action: {
                authenticate(with: provider)
            }
        )
    }

    private func logIn() {
        Task {
            guard let outcome = await viewModel.logIn() else { return }
            switch outcome {
            case let .authenticated(user):
                completeAuthentication(user)
            case let .emailVerification(context):
                showEmailVerification(context)
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
    LogInView(
        repository: MockAuthenticationRepository(delay: .zero),
        showSignUp: {},
        showEmailVerification: { _ in },
        completeAuthentication: { _ in }
    )
}
