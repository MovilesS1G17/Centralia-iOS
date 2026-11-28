import Foundation

enum APIClientError: LocalizedError, Equatable {
    case configurationMissing
    case sessionExpired
    case networkUnavailable
    case invalidResponse
    /// `title` is the short headline some errors carry, e.g. a rejected link:
    /// "This TikTok link isn't a video". `detail` says how to fix it.
    case server(status: Int, code: String, detail: String, email: String?, retryAfter: Int?, title: String? = nil)

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
        case let .server(_, _, detail, _, _, _):
            detail
        }
    }
}

extension APIClientError {
    /// True when the phone couldn't reach the server at all (no connection),
    /// as opposed to the server answering with an error.
    static func isOffline(_ error: Error) -> Bool {
        (error as? APIClientError) == .networkUnavailable
    }
}

private struct APIErrorEnvelope: Decodable {
    let code: String
    let detail: String
    let email: String?
    let retryAfter: Int?
    let title: String?
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
        optionalAuthentication: Bool = false,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        let endpoint = try configuration.endpoint(path: path)
        var request = URLRequest(url: query.isEmpty ? endpoint : endpoint.appending(queryItems: query))
        if let timeout { request.timeoutInterval = timeout }
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
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
                retryAfter: envelope?.retryAfter,
                title: envelope?.title
            )
        }
        return data
    }

    func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = APIDateFormatters.parse(value) { return date }
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
        optionalAuthentication: Bool = false,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> Response {
        try decode(type, from: await send(
            path, method: method, body: body,
            authenticated: authenticated, optionalAuthentication: optionalAuthentication,
            query: query, headers: headers, timeout: timeout
        ))
    }
}

nonisolated enum APIDateFormatters {
    private static let lock = NSLock()

    static func parse(_ value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: value) ?? plain.date(from: value)
    }

    static func timestamp(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return fractional.string(from: date)
    }

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
