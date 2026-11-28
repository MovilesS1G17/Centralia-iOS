import Foundation
import Testing
@testable import Centralia

@MainActor
struct Sprint4AnalyticsTests {
    @Test func trendsReportsTheDisplayedWindowAndCacheSource() async {
        let analytics = RecordedEvents()
        let repository = CachedTrendsRepository(
            fetch: { APITrendsClient.sample(windowDays: $0) },
            disk: InMemoryTrendsDiskStore()
        )
        let model = TrendsViewModel(repository: repository, analytics: analytics)

        await model.load()
        await model.select(windowDays: 30)
        await model.load()

        #expect(analytics.events.map(\.name) == Array(repeating: "trends_loaded", count: 3))
        #expect(analytics.events.compactMap { event in
            if case let .text(source)? = event.properties["source"] { return source }
            return nil
        } == ["network", "network", "memory"])
        #expect(analytics.events.compactMap { event in
            if case let .integer(days)? = event.properties["window_days"] { return days }
            return nil
        } == [7, 30, 30])
    }

    @Test func signingOutDiscardsBufferedEventsAndRejectsNewOnes() async {
        let repository = TestAnalyticsRepository()
        let tracker = BatchingAnalyticsTracker(repository: repository, flushInterval: .seconds(60))
        tracker.track(.watchLaterAdded(videoID: UUID()))

        await tracker.flush()
        #expect(tracker.pendingCount == 1)

        tracker.stop()
        repository.isOnline = true
        tracker.track(.insightsViewed(weeks: 4))
        await tracker.flush()

        #expect(tracker.pendingCount == 0)
        #expect(repository.batches.isEmpty)
    }

    @Test func endingTheSessionClearsItsLocalFeatureData() async throws {
        let trends = CachedTrendsRepository(
            fetch: { APITrendsClient.sample(windowDays: $0) }, disk: InMemoryTrendsDiskStore()
        )
        let services = Sprint4Services(
            dismissals: InMemoryRediscoverDismissals(),
            watchLater: InMemoryWatchLaterStore(),
            trends: trends,
            insights: InMemoryInsightsSnapshotStore()
        )
        let videoID = UUID()
        let now = Date()
        services.dismissals.dismiss(videoID, at: now)
        _ = await services.watchLater.add(videoID: videoID, title: "Saved short", creator: "@creator", at: now)
        await services.insights.save(Insights.compute([], now: now))
        _ = try await trends.load(windowDays: 7)

        await services.endSession().value

        #expect(services.dismissals.active(now: now).isEmpty)
        #expect(await services.watchLater.entries().isEmpty)
        #expect(await services.insights.load() == nil)
        #expect(try await trends.load(windowDays: 7).source == .network)
    }

    private nonisolated final class RecordedEvents: AnalyticsTracking, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [ClientAnalyticsEvent] = []

        var events: [ClientAnalyticsEvent] { lock.withLock { recorded } }

        func track(_ event: ClientAnalyticsEvent) { lock.withLock { recorded.append(event) } }
    }

    @MainActor
    private final class TestAnalyticsRepository: AnalyticsRepository {
        var isOnline = false
        private(set) var batches: [[ClientAnalyticsEvent]] = []

        func record(_ events: [ClientAnalyticsEvent]) async throws {
            guard isOnline else { throw URLError(.notConnectedToInternet) }
            batches.append(events)
        }
    }
}
