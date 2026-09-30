import Foundation

struct APIAuthenticationRepository: AuthenticationRepository {
    private enum Endpoint {
        case register
        case login
        case currentUser
        case updateCurrentUser
    }

    private struct RegistrationRequest: Encodable {
        let email: String
        let password: String
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case email
            case password
            case displayName = "display_name"
        }
    }

    private struct LoginRequest: Encodable {
        let email: String
        let password: String
    }

    private struct UpdateDisplayNameRequest: Encodable {
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    private struct CurrentUserResponse: Decodable {
        let id: UUID
        let email: String
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case id
            case email
            case displayName = "display_name"
        }

        var authenticatedUser: AuthenticatedUser {
            AuthenticatedUser(
                id: id,
                displayName: displayName,
                email: email
            )
        }
    }

    private struct FieldError: Decodable {
        let field: String
        let message: String
    }

    private struct ErrorEnvelope: Decodable {
        let message: String?
        let fieldErrors: [FieldError]

        private enum CodingKeys: String, CodingKey {
            case detail
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let detail = try? container.decode(String.self, forKey: .detail) {
                message = detail
                fieldErrors = []
            } else if let details = try? container.decode([FieldError].self, forKey: .detail) {
                message = nil
                fieldErrors = details
            } else {
                message = nil
                fieldErrors = []
            }
        }
    }

    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokenStore: any AuthenticationTokenStore

    init(
        configuration: APIConfiguration,
        session: URLSession = .shared,
        tokenStore: any AuthenticationTokenStore = KeychainAuthenticationTokenStore()
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
    }

    func createAccount(
        displayName: String,
        email: String,
        password: String
    ) async throws -> AuthenticatedUser {
        let request = try jsonRequest(
            path: "/auth/register",
            method: "POST",
            body: RegistrationRequest(
                email: email,
                password: password,
                displayName: displayName
            )
        )
        let response: TokenResponse = try await perform(request, for: .register)
        return try await storeAndLoadUser(accessToken: response.accessToken)
    }

    func logIn(email: String, password: String) async throws -> AuthenticatedUser {
        let request = try jsonRequest(
            path: "/auth/login",
            method: "POST",
            body: LoginRequest(email: email, password: password)
        )
        let response: TokenResponse = try await perform(request, for: .login)
        return try await storeAndLoadUser(accessToken: response.accessToken)
    }

    func restoreSession() async throws -> AuthenticatedUser? {
        guard let accessToken = try tokenStore.accessToken() else {
            return nil
        }

        do {
            return try await loadCurrentUser(accessToken: accessToken)
        } catch AuthenticationError.sessionExpired {
            try tokenStore.clearAccessToken()
            return nil
        }
    }

    func updateDisplayName(
        _ displayName: String,
        for _: AuthenticatedUser
    ) async throws -> AuthenticatedUser {
        guard let accessToken = try tokenStore.accessToken() else {
            throw AuthenticationError.sessionExpired
        }

        var request = try jsonRequest(
            path: "/me",
            method: "PATCH",
            body: UpdateDisplayNameRequest(displayName: displayName)
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let response: CurrentUserResponse = try await perform(request, for: .updateCurrentUser)
        return response.authenticatedUser
    }

    func authenticate(with provider: AuthenticationProvider) async throws -> AuthenticatedUser {
        throw AuthenticationError.providerUnavailable
    }

    func requestPasswordReset(for email: String) async throws {
        throw AuthenticationError.resetUnavailable
    }

    func signOut() async throws {
        try tokenStore.clearAccessToken()
    }

    private func storeAndLoadUser(accessToken: String) async throws -> AuthenticatedUser {
        do {
            try tokenStore.save(accessToken: accessToken)
            return try await loadCurrentUser(accessToken: accessToken)
        } catch {
            try? tokenStore.clearAccessToken()
            throw error
        }
    }

    private func loadCurrentUser(accessToken: String) async throws -> AuthenticatedUser {
        var request = URLRequest(url: configuration.endpoint(path: "/me"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let response: CurrentUserResponse = try await perform(request, for: .currentUser)
        return response.authenticatedUser
    }

    private func jsonRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        for endpoint: Endpoint
    ) async throws -> Response {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AuthenticationError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthenticationError.networkUnavailable
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw apiError(
                statusCode: httpResponse.statusCode,
                endpoint: endpoint,
                data: data
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AuthenticationError.requestFailed
        }
    }

    private func apiError(statusCode: Int, endpoint: Endpoint, data: Data) -> AuthenticationError {
        let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)

        if statusCode == 422, let fieldError = envelope?.fieldErrors.first {
            return .validation(
                field: AuthenticationField(rawValue: fieldError.field) ?? .unknown,
                message: fieldError.message
            )
        }

        switch (endpoint, statusCode) {
        case (.register, 409):
            return .accountAlreadyExists
        case (.login, 401):
            return .invalidCredentials
        case (.currentUser, 401), (.updateCurrentUser, 401):
            return .sessionExpired
        default:
            return .requestFailed
        }
    }
}
