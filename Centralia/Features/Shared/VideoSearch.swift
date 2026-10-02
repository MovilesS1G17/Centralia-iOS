import Foundation

enum SearchFolderFilter: Equatable, Sendable {
    case all
    case unorganized
    case folder(UUID)
}

/// What the user asked for. Empty fields do not narrow the result.
struct VideoSearchCriteria: Equatable, Sendable {
    var text = ""
    var platform: VideoPlatform?
    var creator: String?
    var folder: SearchFolderFilter = .all
    /// A video must carry every selected tag (case-insensitive).
    var tags: Set<String> = []

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
            if let platform = criteria.platform, video.platform != platform {
                return false
            }

            if let creator = criteria.creator, video.creator != creator {
                return false
            }

            switch criteria.folder {
            case .all:
                break
            case .unorganized:
                if video.folderID != nil { return false }
            case let .folder(folderID):
                if video.folderID != folderID { return false }
            }

            guard criteria.tags.allSatisfy({ TagCatalog.contains(video.tags, $0) }) else {
                return false
            }

            guard !terms.isEmpty else { return true }

            let values = searchableValues(for: video, folderName: video.folderID.flatMap { folderNames[$0] })
            return terms.allSatisfy { term in
                values.contains { $0.localizedStandardContains(term) }
            }
        }
    }

    private static func searchableValues(for video: VideoItem, folderName: String?) -> [String] {
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
