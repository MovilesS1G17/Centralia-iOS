import Foundation

struct APIConfiguration: Sendable {
    let baseURL: URL?

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    static var current: APIConfiguration {
        let environment = ProcessInfo.processInfo.environment["CENTRALIA_API_BASE_URL"]
        let bundled = Bundle.main.object(forInfoDictionaryKey: "CentraliaAPIBaseURL") as? String
        let value = [environment, bundled].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return APIConfiguration(baseURL: value.flatMap(URL.init(string:)))
    }

    func endpoint(path: String) throws -> URL {
        guard let baseURL,
              let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil else {
            throw APIClientError.configurationMissing
        }
        return baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    func streamURL(for signedPath: String) throws -> URL {
        guard signedPath.hasPrefix("/v1/streams/"),
              let baseURL,
              let url = URL(string: signedPath, relativeTo: baseURL)?.absoluteURL,
              url.scheme == baseURL.scheme,
              url.host == baseURL.host,
              url.port == baseURL.port else {
            throw APIClientError.invalidResponse
        }
        return url
    }
}
