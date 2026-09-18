import Foundation

struct MockVideoImportPipeline: VideoImportPipeline {
    private struct Fixture: Sendable {
        let platform: VideoPlatform
        let creator: String
        let durationSeconds: Int
        let caption: String
        let transcript: String?
        let onScreenText: String?
        let summary: String
        let tags: [String]
        let suggestedFolder: String
    }

    private let delay: Duration

    init(delay: Duration = .milliseconds(420)) {
        self.delay = delay
    }

    func detectPlatform(from sourceURL: URL) async throws -> VideoPlatform {
        try await pause()

        guard sourceURL.scheme?.lowercased() == "https",
              let host = sourceURL.host?.lowercased() else {
            throw VideoImportError.invalidURL
        }

        let path = sourceURL.path.lowercased()

        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            guard path.contains("/video/") || host == "vm.tiktok.com" else {
                throw VideoImportError.unsupportedSource
            }
            return .tiktok
        }

        if host == "instagram.com" || host.hasSuffix(".instagram.com") {
            guard path.contains("/reel/") || path.contains("/reels/") else {
                throw VideoImportError.unsupportedInstagramPost
            }
            return .instagramReel
        }

        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            guard path.contains("/shorts/") else {
                throw VideoImportError.unsupportedYouTubeVideo
            }
            return .youtubeShort
        }

        throw VideoImportError.unsupportedSource
    }

    func extractMetadata(
        from sourceURL: URL,
        platform: VideoPlatform
    ) async throws -> ImportedVideoMetadata {
        try await pause()
        let fixture = fixture(for: sourceURL, platform: platform)

        return ImportedVideoMetadata(
            sourceURL: sourceURL,
            platform: fixture.platform,
            creator: fixture.creator,
            durationSeconds: fixture.durationSeconds,
            sourceCaption: fixture.caption,
            transcript: fixture.transcript,
            extractedOnScreenText: fixture.onScreenText,
            generatedSummary: fixture.summary
        )
    }

    func generateTags(for metadata: ImportedVideoMetadata) async throws -> [String] {
        try await pause()
        return fixture(for: metadata.sourceURL, platform: metadata.platform).tags
    }

    func suggestFolder(
        for metadata: ImportedVideoMetadata,
        tags: [String]
    ) async throws -> String? {
        try await pause()
        return fixture(for: metadata.sourceURL, platform: metadata.platform).suggestedFolder
    }

    private func pause() async throws {
        guard delay > .zero else {
            try Task.checkCancellation()
            return
        }

        try await Task.sleep(for: delay)
    }

    private func fixture(for sourceURL: URL, platform: VideoPlatform) -> Fixture {
        let matches = Self.fixtures.filter { $0.platform == platform }
        let index = stableIndex(for: sourceURL.absoluteString, upperBound: matches.count)
        return matches[index]
    }

    private func stableIndex(for value: String, upperBound: Int) -> Int {
        let hash = value.utf8.reduce(UInt64(5_381)) { partialResult, byte in
            ((partialResult << 5) &+ partialResult) &+ UInt64(byte)
        }
        return Int(hash % UInt64(upperBound))
    }

    private static let fixtures: [Fixture] = [
        Fixture(
            platform: .tiktok,
            creator: "@roomreset",
            durationSeconds: 28,
            caption: "Wait for the final result.",
            transcript: "Use vertical storage and keep the desk close to natural light in a small studio.",
            onScreenText: "small studio reset",
            summary: "Tiny studio ideas",
            tags: ["studio", "organization", "interiors"],
            suggestedFolder: "Spaces"
        ),
        Fixture(
            platform: .tiktok,
            creator: "@slowmornings",
            durationSeconds: 22,
            caption: "Needed this today.",
            transcript: nil,
            onScreenText: "a slower morning routine",
            summary: "A calmer morning",
            tags: ["morning", "routine", "wellbeing"],
            suggestedFolder: "Wellbeing"
        ),
        Fixture(
            platform: .tiktok,
            creator: "@typefoundry",
            durationSeconds: 34,
            caption: "Save this for your next layout.",
            transcript: "Start with contrast, then use spacing and scale to make the hierarchy obvious.",
            onScreenText: "visual hierarchy in three steps",
            summary: "Build clearer visual hierarchy",
            tags: ["design", "typography", "layout"],
            suggestedFolder: "Design"
        ),
        Fixture(
            platform: .instagramReel,
            creator: "@studiomarta",
            durationSeconds: 41,
            caption: "The third one changed everything.",
            transcript: "Choose one dominant color, one supporting color, and one small accent color.",
            onScreenText: "three colour rule",
            summary: "Three color rules",
            tags: ["color", "design", "visual identity"],
            suggestedFolder: "Design"
        ),
        Fixture(
            platform: .instagramReel,
            creator: "@softforms",
            durationSeconds: 36,
            caption: "One more for the shelf.",
            transcript: "Center the clay before opening the form and keep both elbows anchored.",
            onScreenText: "wheel throwing basics",
            summary: "Centering clay on the wheel",
            tags: ["ceramics", "craft", "tutorial"],
            suggestedFolder: "Design"
        ),
        Fixture(
            platform: .instagramReel,
            creator: "@tinyspaces",
            durationSeconds: 33,
            caption: "A corner that finally works.",
            transcript: "Use one floating shelf and a compact task light to separate the workspace.",
            onScreenText: "home workspace",
            summary: "A workspace for small rooms",
            tags: ["workspace", "interiors", "organization"],
            suggestedFolder: "Spaces"
        ),
        Fixture(
            platform: .youtubeShort,
            creator: "@swiftminute",
            durationSeconds: 48,
            caption: "This transition feels so much better.",
            transcript: "Use a matched geometry effect to preserve spatial continuity between SwiftUI states.",
            onScreenText: "matchedGeometryEffect",
            summary: "Smoother SwiftUI transitions",
            tags: ["SwiftUI", "animation", "iOS"],
            suggestedFolder: "Design"
        ),
        Fixture(
            platform: .youtubeShort,
            creator: "@quickplate",
            durationSeconds: 54,
            caption: "Dinner sorted.",
            transcript: "Boil the pasta while the tomatoes, garlic, and olive oil cook in the same pan.",
            onScreenText: "20 minute pasta",
            summary: "Pasta in 20 minutes",
            tags: ["pasta", "dinner", "quick recipes"],
            suggestedFolder: "Recipes"
        ),
        Fixture(
            platform: .youtubeShort,
            creator: "@dailyreset",
            durationSeconds: 39,
            caption: "A simple way to end the day.",
            transcript: "Put tomorrow's three priorities on paper and move your phone away from the bed.",
            onScreenText: "five minute evening reset",
            summary: "A five-minute evening reset",
            tags: ["routine", "focus", "wellbeing"],
            suggestedFolder: "Wellbeing"
        )
    ]
}
