import Foundation

private struct ClientEventsBody: Encodable {
    let events: [ClientAnalyticsEvent]
}

private struct ClientEventsResponse: Decodable {
    let accepted: Int
    let rejected: Int
}

struct APIAnalyticsRepository: AnalyticsRepository {
    let client: APIClient
    // Buffered events keep the bearer token of the session that produced them.
    var sessionToken: String? = nil
    var isOnline: () -> Bool = { true }

    func record(_ events: [ClientAnalyticsEvent]) async throws {
        guard !events.isEmpty else { return }
        guard isOnline() else { throw APIClientError.networkUnavailable }
        let body = try client.encode(ClientEventsBody(events: events))
        let headers = sessionToken.map { ["Authorization": "Bearer \($0)"] } ?? [:]
        let result = try await client.request(
            ClientEventsResponse.self,
            path: "/v1/analytics/events", method: "POST", body: body,
            authenticated: false, optionalAuthentication: sessionToken == nil,
            headers: headers, timeout: 10
        )
        guard result.accepted == events.count, result.rejected == 0 else {
            throw APIClientError.invalidResponse
        }
    }
}
