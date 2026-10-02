import Foundation

enum APIClientError: LocalizedError, Equatable {
    case configurationMissing
    case sessionExpired
    case networkUnavailable
    case invalidResponse
    case server(status: Int, code: String, detail: String, email: String?, retryAfter: Int?)

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            "Configure the Centralia API URL before using the live app."
        case .sessionExpired:
            "Your session has ended. Please sign in again."
        case .networkUnavailable:
            "We couldn't reach Centralia. Check your connection and try again."
        case .invalidResponse:
            "Centralia returned an unexpected response. Please try again."
        case let .server(_, _, detail, _, _):
            detail
        }
    }
}

private struct APIErrorEnvelope: Decodable {
    let code: String
    let detail: String
    let email: String?
    let retryAfter: Int?
}

struct APIClient {
    let configuration: APIConfiguration
    let session: URLSession
    let tokenStore: any AuthenticationTokenStore

    init(
        configuration: APIConfiguration = .current,
        session: URLSession = .shared,
        tokenStore: any AuthenticationTokenStore = KeychainAuthenticationTokenStore()
    ) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
    }

    func encode<Body: Encodable>(_ body: Body) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(body)
    }

    func send(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        authenticated: Bool = true,
        optionalAuthentication: Bool = false
    ) async throws -> Data {
        var request = URLRequest(url: try configuration.endpoint(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authenticated || optionalAuthentication {
            let token = try tokenStore.accessToken()
            if authenticated && token == nil {
                throw APIClientError.sessionExpired
            }
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIClientError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            if authenticated && http.statusCode == 401 {
                throw APIClientError.sessionExpired
            }
            throw APIClientError.server(
                status: http.statusCode,
                code: envelope?.code ?? "http_\(http.statusCode)",
                detail: envelope?.detail ?? "Centralia couldn't complete this request. Please try again.",
                email: envelope?.email,
                retryAfter: envelope?.retryAfter
            )
        }
        return data
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIClientError.invalidResponse
        }
    }

    func request<Response: Decodable>(
        _ type: Response.Type,
        path: String,
        method: String = "GET",
        body: Data? = nil,
        authenticated: Bool = true,
        optionalAuthentication: Bool = false
    ) async throws -> Response {
        try decode(type, from: await send(
            path, method: method, body: body,
            authenticated: authenticated, optionalAuthentication: optionalAuthentication
        ))
    }
}
