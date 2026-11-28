import Foundation
import Testing
@testable import Centralia

struct TrendsCacheTests {
    @Test func reusesMemoryAndDiskAndFallsBackToStaleData() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let feed = Feed()
        let original = CachedTrendsRepository(
            fetch: { try await feed.fetch(days: $0) },
            disk: FileTrendsDiskStore(directory: directory),
            now: { start }
        )

        let first = try await original.load(windowDays: 7)
        #expect(first.source == .network)
        #expect(try await original.load(windowDays: 7).source == .memory)

        let relaunched = CachedTrendsRepository(
            fetch: { try await feed.fetch(days: $0) },
            disk: FileTrendsDiskStore(directory: directory),
            now: { start.addingTimeInterval(30) }
        )
        #expect(try await relaunched.load(windowDays: 7).source == .disk)
        #expect(await feed.calls == [7])

        await feed.goOffline()
        let expired = CachedTrendsRepository(
            fetch: { try await feed.fetch(days: $0) },
            disk: FileTrendsDiskStore(directory: directory),
            now: { start.addingTimeInterval(600) }
        )
        let fallback = try await expired.load(windowDays: 7)
        #expect(fallback.source == .disk)
        #expect(fallback.isStale)
        #expect(fallback.trends == first.trends)
        await #expect(throws: TrendsUnavailableError.self) {
            try await expired.load(windowDays: 30)
        }
    }

    @Test func keepsWindowsSeparateAndRefreshesOnDemand() async throws {
        let feed = Feed()
        let repository = CachedTrendsRepository(
            fetch: { try await feed.fetch(days: $0) }, disk: InMemoryTrendsDiskStore()
        )

        #expect(try await repository.load(windowDays: 7).trends.windowDays == 7)
        #expect(try await repository.load(windowDays: 30).trends.windowDays == 30)
        #expect(try await repository.load(windowDays: 7).source == .memory)
        #expect(try await repository.load(windowDays: 7, forceRefresh: true).source == .network)
        #expect(await feed.calls == [7, 30, 7])

        await repository.clear()
        #expect(try await repository.load(windowDays: 30).source == .network)
        #expect(await feed.calls == [7, 30, 7, 30])
    }

    private actor Feed {
        private(set) var calls: [Int] = []
        private var online = true

        func goOffline() { online = false }

        func fetch(days: Int) throws -> Trends {
            calls.append(days)
            guard online else { throw URLError(.notConnectedToInternet) }
            return Trends(
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                windowDays: days,
                minUsers: 3,
                totalSaves: days,
                categories: [TrendItem(name: "Recipes", saves: days, users: 3)],
                tags: [],
                platformCounts: ["tiktok": days]
            )
        }
    }
}
