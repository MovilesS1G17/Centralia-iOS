import Foundation

struct SearchResult: Equatable, Sendable {
    let videos: [VideoItem]
    let totalCount: Int
}

protocol SearchRepository: Sendable {
    /// Calls the backend's Specification-based `GET /videos` search. `query`
    /// is expected to already be a single term — multi-term AND matching
    /// across fields stays a client-side concern (`SearchViewModel.filteredVideos`),
    /// since the backend's `query` param only does a single substring match.
    func search(
        query: String?,
        platform: VideoPlatform?,
        creator: String?,
        folderID: UUID?,
        tag: String?,
        limit: Int?,
        offset: Int
    ) async throws -> SearchResult

    /// Fire-and-forget: reports the client-measured latency of a search that
    /// had at least one active filter/query. Never throws, never blocks the
    /// caller — failures are swallowed internally.
    func reportSearchCompleted(durationMs: Int, resultCount: Int, filterCount: Int)
}
