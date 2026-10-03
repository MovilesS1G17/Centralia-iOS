import Foundation

enum VideoPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case tiktok
    case instagramReel
    case youtubeShort

    var id: Self { self }

    var displayName: String {
        switch self {
        case .tiktok:
            "TikTok"
        case .instagramReel:
            "Instagram Reel"
        case .youtubeShort:
            "YouTube Short"
        }
    }

    var filterName: String {
        switch self {
        case .tiktok:
            "TikTok"
        case .instagramReel:
            "Reels"
        case .youtubeShort:
            "Shorts"
        }
    }
}

enum ContentAnalysisStatus: String, Codable, Sendable {
    case pending
    case completed
    case unavailable
    case failed
}

struct VideoItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let sourceURL: URL
    let platform: VideoPlatform
    let creator: String
    let durationSeconds: Int
    let sourceCaption: String?
    let transcript: String?
    let extractedOnScreenText: String?
    let generatedSummary: String?
    var customTitle: String?
    var folderID: UUID?
    var tags: [String]
    var note: String?
    let savedAt: Date
    let analysisStatus: ContentAnalysisStatus
    /// Cover image resolved by the API when the source platform exposes one.
    var thumbnailURL: URL? = nil
    /// Platform embed URL, retained for web-player fallbacks and future use.
    var embedURL: URL? = nil

    var creatorDisplayName: String { creator.isEmpty ? "Creator unavailable" : creator }

    var displayTitle: String {
        if let customTitle = customTitle?.nonEmptyTrimmed {
            return customTitle
        }

        if let generatedSummary = generatedSummary?.nonEmptyTrimmed {
            return generatedSummary
        }

        if let sourceCaption = sourceCaption?.nonEmptyTrimmed {
            return sourceCaption
        }

        return creator.isEmpty ? "Saved short" : "Short by \(creator)"
    }

    var formattedDuration: String {
        guard durationSeconds > 0 else { return "Duration unavailable" }
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Uses the API result first and derives the predictable YouTube cover
    /// when an older record does not include one.
    var coverURL: URL? {
        thumbnailURL ?? ShortEmbed.fallbackThumbnailURL(for: sourceURL, platform: platform)
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
