import Foundation

struct APIAuthenticationRepository: V3AuthenticationRepository {
    private struct EmailPasswordBody: Encodable {
        let email: String
        let password: String
    }

    private struct EmailBody: Encodable {
        let email: String
    }

    private struct CodeBody: Encodable {
        let email: String
        let code: String
    }

    private struct ResetConfirmBody: Encodable {
        let email: String
        let code: String
        let newPassword: String
    }

    private struct ProfileUpdateBody: Encodable {
        let displayName: String
        let email: String
    }

    private let client: APIClient

    init(
        configuration: APIConfiguration = .current,
        session: URLSession = .shared,
        tokenStore: any AuthenticationTokenStore = KeychainAuthenticationTokenStore()
    ) {
        client = APIClient(configuration: configuration, session: session, tokenStore: tokenStore)
    }

    init(client: APIClient) {
        self.client = client
    }

    func register(email: String, password: String) async throws -> VerificationPending {
        do {
            let body = try client.encode(EmailPasswordBody(email: email, password: password))
            let pending = try await client.request(
                VerificationPendingDTO.self, path: "/v1/auth/register", method: "POST",
                body: body, authenticated: false
            )
            return pending.model
        } catch {
            throw map(error)
        }
    }

    func createAccount(displayName _: String, email: String, password: String) async throws -> AuthenticatedUser {
        let pending = try await register(email: email, password: password)
        throw AuthenticationError.verificationRequired(
            email: pending.email, resendAvailableIn: pending.resendAvailableIn
        )
    }

    func verifyEmail(email: String, code: String) async throws -> AuthenticatedUser {
        try await authenticate(
            path: "/v1/auth/verify-email", body: CodeBody(email: email, code: code)
        )
    }

    func resendVerificationCode(email: String) async throws -> VerificationPending {
        do {
            let body = try client.encode(EmailBody(email: email))
            let pending = try await client.request(
                VerificationPendingDTO.self, path: "/v1/auth/verification-code", method: "POST",
                body: body, authenticated: false
            )
            return pending.model
        } catch {
            throw map(error)
        }
    }

    func logIn(email: String, password: String) async throws -> AuthenticatedUser {
        try await authenticate(
            path: "/v1/auth/login", body: EmailPasswordBody(email: email, password: password)
        )
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws -> AuthenticatedUser {
        try await authenticate(
            path: "/v1/auth/password-reset/confirm",
            body: ResetConfirmBody(email: email, code: code, newPassword: newPassword)
        )
    }

    func requestPasswordReset(for email: String) async throws {
        do {
            let body = try client.encode(EmailBody(email: email))
            _ = try await client.request(
                PasswordResetAcceptedDTO.self, path: "/v1/auth/password-reset", method: "POST",
                body: body, authenticated: false
            )
        } catch {
            throw map(error)
        }
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        guard try client.tokenStore.accessToken() != nil else { return nil }
        do {
            return try await currentUser()
        } catch AuthenticationError.sessionExpired {
            try client.tokenStore.clearAccessToken()
            return nil
        }
    }

    func updateDisplayName(_ displayName: String, for user: AuthenticatedUser) async throws -> AuthenticatedUser {
        guard let email = user.email else { throw AuthenticationError.requestFailed }
        do {
            let body = try client.encode(ProfileUpdateBody(displayName: displayName, email: email))
            let profile = try await client.request(
                UserProfileDTO.self, path: "/v1/me", method: "PATCH", body: body
            )
            return profile.authenticatedUser
        } catch {
            throw map(error)
        }
    }

    func authenticate(with _: AuthenticationProvider) async throws -> AuthenticatedUser {
        throw AuthenticationError.providerUnavailable
    }

    func signOut() async throws {
        _ = try? await client.send("/v1/auth/logout", method: "POST")
        try client.tokenStore.clearAccessToken()
    }

    private func currentUser() async throws -> AuthenticatedUser {
        do {
            let profile = try await client.request(UserProfileDTO.self, path: "/v1/me")
            return profile.authenticatedUser
        } catch {
            throw map(error)
        }
    }

    private func authenticate<Body: Encodable>(path: String, body: Body) async throws -> AuthenticatedUser {
        do {
            let data = try client.encode(body)
            let session = try await client.request(
                AuthSessionDTO.self, path: path, method: "POST", body: data, authenticated: false
            )
            guard session.tokenType.lowercased() == "bearer" else {
                throw APIClientError.invalidResponse
            }
            try client.tokenStore.save(accessToken: session.accessToken)
            return session.user.model
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> Error {
        guard let api = error as? APIClientError else { return error }
        switch api {
        case .sessionExpired:
            return AuthenticationError.sessionExpired
        case .networkUnavailable:
            return AuthenticationError.networkUnavailable
        case .configurationMissing, .invalidResponse:
            return AuthenticationError.serverMessage(api.localizedDescription)
        case let .server(_, code, detail, email, retryAfter):
            switch code {
            case "invalid_credentials": return AuthenticationError.invalidCredentials
            case "account_already_exists": return AuthenticationError.accountAlreadyExists
            case "email_not_verified":
                return AuthenticationError.verificationRequired(
                    email: email ?? "", resendAvailableIn: retryAfter ?? 0
                )
            case "invalid_email": return AuthenticationError.validation(field: .email, message: detail)
            case "weak_password", "common_password":
                return AuthenticationError.validation(field: .password, message: detail)
            case "display_name_required":
                return AuthenticationError.validation(field: .displayName, message: detail)
            case "not_authenticated": return AuthenticationError.sessionExpired
            default: return AuthenticationError.serverMessage(detail)
            }
        }
    }
}
