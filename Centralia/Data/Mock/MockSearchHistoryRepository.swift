import Foundation

actor MockSearchHistoryRepository: SearchHistoryRepository {
    private struct Snapshot: Codable, Sendable {
        let schemaVersion: Int
        var queries: [String]
    }

    private let store: MockDataStore
    private let filename: String
    private let maximumQueryCount: Int

    init(
        store: MockDataStore = MockDataStore(),
        filename: String = "search-history-v1.json",
        maximumQueryCount: Int = 8
    ) {
        self.store = store
        self.filename = filename
        self.maximumQueryCount = maximumQueryCount
    }

    func recentSearches() async throws -> [String] {
        try await snapshot().queries
    }

    func recordSearch(_ query: String) async throws {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        var value = try await snapshot()
        value.queries.removeAll {
            $0.localizedCaseInsensitiveCompare(trimmedQuery) == .orderedSame
        }
        value.queries.insert(trimmedQuery, at: 0)
        value.queries = Array(value.queries.prefix(maximumQueryCount))
        try await store.save(value, to: filename)
    }

    func clearSearchHistory() async throws {
        var value = try await snapshot()
        value.queries.removeAll()
        try await store.save(value, to: filename)
    }

    private func snapshot() async throws -> Snapshot {
        try await store.load(Snapshot.self, from: filename, seed: Self.seed)
    }

    private static let seed = Snapshot(
        schemaVersion: 1,
        queries: ["SwiftUI animation", "pasta", "small studio"]
    )
}
