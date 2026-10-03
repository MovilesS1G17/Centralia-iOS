import Foundation

/// Derives a short's player and a safe cover-image fallback from its source URL.
/// The API remains the source of metadata; this only supports records created
/// before the API began returning a thumbnail.
enum ShortEmbed {
    /// YouTube exposes a cover at a predictable URL. TikTok and Instagram do
    /// not offer a comparable public URL, so their cards retain their colour
    /// until the backend resolves metadata.
    static func fallbackThumbnailURL(for sourceURL: URL, platform: VideoPlatform) -> URL? {
        guard platform == .youtubeShort,
              let id = videoID(from: sourceURL, platform: platform) else {
            return nil
        }

        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }

    private static func videoID(from sourceURL: URL, platform: VideoPlatform) -> String? {
        guard platform == .youtubeShort else { return nil }

        let segments = sourceURL.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard let shortsIndex = segments.firstIndex(of: "shorts"),
              shortsIndex + 1 < segments.count else {
            return nil
        }

        let id = String(segments[shortsIndex + 1].prefix { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
        })
        return id.count >= 6 ? id : nil
    }
}
