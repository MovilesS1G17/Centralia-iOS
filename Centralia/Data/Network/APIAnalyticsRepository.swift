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

    func record(_ events: [ClientAnalyticsEvent]) async throws {
        guard !events.isEmpty else { return }
        let body = try client.encode(ClientEventsBody(events: events))
        let result = try await client.request(
            ClientEventsResponse.self,
            path: "/v1/analytics/events", method: "POST", body: body,
            authenticated: false, optionalAuthentication: true
        )
        guard result.accepted == events.count, result.rejected == 0 else {
            throw APIClientError.invalidResponse
        }
    }
}
