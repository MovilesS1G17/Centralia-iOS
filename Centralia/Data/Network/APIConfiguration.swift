import Foundation

struct APIConfiguration: Sendable {
    let baseURL: URL

    static let current: APIConfiguration = {
        let configuredURL = ProcessInfo.processInfo.environment["CENTRALIA_API_BASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "CentraliaAPIBaseURL") as? String
            ?? "http://127.0.0.1:8000"

        guard let baseURL = URL(string: configuredURL),
              let scheme = baseURL.scheme,
              ["http", "https"].contains(scheme) else {
            preconditionFailure("CENTRALIA_API_BASE_URL must be a valid HTTP(S) URL.")
        }

        return APIConfiguration(baseURL: baseURL)
    }()

    func endpoint(path: String) -> URL {
        baseURL.appending(path: path)
    }
}
