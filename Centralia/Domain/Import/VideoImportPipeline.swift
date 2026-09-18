import Foundation

enum VideoImportStage: Int, CaseIterable, Equatable, Sendable {
    case detectingPlatform
    case extractingMetadata
    case generatingTags
    case suggestingFolder

    var displayName: String {
        switch self {
        case .detectingPlatform:
            "Detecting platform…"
        case .extractingMetadata:
            "Extracting metadata…"
        case .generatingTags:
            "Generating tag suggestions…"
        case .suggestingFolder:
            "Suggesting a folder…"
        }
    }
}

struct ImportedVideoMetadata: Equatable, Sendable {
    let sourceURL: URL
    let platform: VideoPlatform
    let creator: String
    let durationSeconds: Int
    let sourceCaption: String?
    let transcript: String?
    let extractedOnScreenText: String?
    let generatedSummary: String?

    var formattedDuration: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum VideoImportError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedSource
    case unsupportedYouTubeVideo
    case unsupportedInstagramPost

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a complete link beginning with https://."
        case .unsupportedSource:
            "Centralia currently supports TikTok videos, Instagram Reels, and YouTube Shorts only."
        case .unsupportedYouTubeVideo:
            "This looks like a regular YouTube video. Paste a YouTube Shorts link instead."
        case .unsupportedInstagramPost:
            "This looks like an Instagram post. Paste an Instagram Reel link instead."
        }
    }
}

protocol VideoImportPipeline {
    func detectPlatform(from sourceURL: URL) async throws -> VideoPlatform
    func extractMetadata(
        from sourceURL: URL,
        platform: VideoPlatform
    ) async throws -> ImportedVideoMetadata
    func generateTags(for metadata: ImportedVideoMetadata) async throws -> [String]
    func suggestFolder(
        for metadata: ImportedVideoMetadata,
        tags: [String]
    ) async throws -> String?
}
