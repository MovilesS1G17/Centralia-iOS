import Foundation

/// Local stand-in for `APISearchRepository`, used by `DependencyContainer.mock()`.
/// Mirrors the backend's Specification semantics (single substring `query`
/// across title/caption/creator, exact case-insensitive `creator`, exact
/// `platform`/`folderID`, exact case-insensitive `tag`) over whatever the
/// injected `VideoItemRepository` currently holds.
struct MockSearchRepository: SearchRepository {
    let videoRepository: any VideoItemRepository

    func search(
        query: String?,
        platform: VideoPlatform?,
        creator: String?,
        folderID: UUID?,
        tag: String?,
        limit: Int?,
        offset: Int
    ) async throws -> SearchResult {
        let matched = try await videoRepository.videos().filter { video in
            if let query, !query.isEmpty {
                let pattern = query
                let haystacks = [video.customTitle, video.sourceCaption, video.creator]
                guard haystacks.contains(where: { $0?.localizedCaseInsensitiveContains(pattern) == true }) else {
                    return false
                }
            }
            if let platform, video.platform != platform { return false }
            if let creator, video.creator.caseInsensitiveCompare(creator) != .orderedSame { return false }
            if let folderID, video.folderID != folderID { return false }
            if let tag, !video.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                return false
            }
            return true
        }

        let total = matched.count
        guard let limit else { return SearchResult(videos: matched, totalCount: total) }
        let page = Array(matched.dropFirst(offset).prefix(limit))
        return SearchResult(videos: page, totalCount: total)
    }

    func reportSearchCompleted(durationMs: Int, resultCount: Int, filterCount: Int) {
        // No backend in mock mode — nothing to report.
    }
}
