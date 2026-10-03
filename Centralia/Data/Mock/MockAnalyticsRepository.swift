import Foundation

struct MockAnalyticsRepository: AnalyticsRepository {
    func record(_ events: [ClientAnalyticsEvent]) async throws {}
}
