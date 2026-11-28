import Foundation

nonisolated enum SearchFolderFilter: Codable, Hashable, Sendable {
    case all
    case unorganized
    case folder(UUID)
}

/// What the user asked for. Empty fields do not narrow the result.
nonisolated struct VideoSearchCriteria: Codable, Hashable, Sendable {
    var text = ""
    var platform: VideoPlatform?
    var creator: String?
    var folder: SearchFolderFilter = .all
    /// A video must carry every selected tag (case-insensitive).
    var tags: Set<String> = []

    var hasFilters: Bool { platform != nil || creator != nil || folder != .all || !tags.isEmpty }
    var isSaveable: Bool { hasFilters || !terms.isEmpty }

    var terms: [String] {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }
}

/// Client-side search over the saved library. The V3 backend only lists videos
/// (`GET /v1/videos`), so matching happens here.
enum VideoSearch {
    static func filter(
        _ videos: [VideoItem],
        criteria: VideoSearchCriteria,
        folderNames: [UUID: String] = [:]
    ) -> [VideoItem] {
        let terms = criteria.terms

        return videos.filter { video in
            guard matchesFilters(video, criteria: criteria) else { return false }
            guard !terms.isEmpty else { return true }

            let values = searchableValues(for: video, folderName: video.folderID.flatMap { folderNames[$0] })
            return terms.allSatisfy { term in
                values.contains { $0.localizedStandardContains(term) }
            }
        }
    }

    fileprivate static func matchesFilters(_ video: VideoItem, criteria: VideoSearchCriteria) -> Bool {
        if let platform = criteria.platform, video.platform != platform { return false }
        if let creator = criteria.creator, video.creator != creator { return false }

        switch criteria.folder {
        case .all:
            break
        case .unorganized:
            if video.folderID != nil { return false }
        case let .folder(folderID):
            if video.folderID != folderID { return false }
        }

        return criteria.tags.allSatisfy { TagCatalog.contains(video.tags, $0) }
    }

    fileprivate static func searchableValues(for video: VideoItem, folderName: String?) -> [String] {
        var values = [video.creator]
        values.append(contentsOf: [
            video.customTitle,
            video.sourceCaption,
            video.generatedSummary,
            video.transcript,
            folderName
        ].compactMap { $0 })
        values.append(contentsOf: video.tags)
        return values
    }
}

/// Keeps the searchable fields for one library snapshot, in the same order as the videos.
struct VideoSearchIndex {
    private let videos: [VideoItem]
    private let fields: [[SearchText]]
    private let locale: Locale

    init(_ videos: [VideoItem], folderNames: [UUID: String] = [:], locale: Locale = .current) {
        self.videos = videos
        self.locale = locale
        fields = videos.map { video in
            let folderName = video.folderID.flatMap { folderNames[$0] }
            return VideoSearch.searchableValues(for: video, folderName: folderName).map {
                SearchText($0, locale: locale)
            }
        }
    }

    func filter(criteria: VideoSearchCriteria) -> [VideoItem] {
        let terms = criteria.terms.map { SearchText($0, locale: locale) }

        return videos.indices.compactMap { index in
            let video = videos[index]
            guard VideoSearch.matchesFilters(video, criteria: criteria) else { return nil }
            let matches = terms.allSatisfy { term in fields[index].contains { $0.matches(term) } }
            return matches ? video : nil
        }
    }

    private struct SearchText {
        let original: String
        let foldedASCII: String?

        init(_ original: String, locale: Locale) {
            self.original = original
            // Unicode expansions and grapheme clusters can match differently
            // after folding. Keep Foundation's localized comparison for them.
            if original.utf8.allSatisfy({ (32...126).contains($0) }) {
                foldedASCII = original.folding(options: .caseInsensitive, locale: locale)
            } else {
                foldedASCII = nil
            }
        }

        func matches(_ term: SearchText) -> Bool {
            if let field = foldedASCII, let needle = term.foldedASCII {
                return field.range(of: needle, options: .literal) != nil
            }
            return original.localizedStandardContains(term.original)
        }
    }
}
