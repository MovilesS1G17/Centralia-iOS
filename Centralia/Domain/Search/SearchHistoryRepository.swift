protocol SearchHistoryRepository {
    func recentSearches() async throws -> [String]
    func recordSearch(_ query: String) async throws
    func clearSearchHistory() async throws
}
