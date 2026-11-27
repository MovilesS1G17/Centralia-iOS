import Foundation

/// Derives a short's player or cover when the API metadata is unavailable.
enum ShortEmbed {
    static func fallbackPlayerURL(for sourceURL: URL, platform: VideoPlatform) -> URL? {
        guard sourceURL.scheme?.lowercased() == "https", let host = sourceURL.host?.lowercased() else { return nil }
        let path = sourceURL.path.split(separator: "/")
        guard path.count >= 2 else { return nil }

        switch platform {
        case .youtubeShort:
            guard ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host),
                  path[0] == "shorts", validCode(path[1]) else { return nil }
            return URL(string: "https://www.youtube.com/embed/\(path[1])?autoplay=1&playsinline=1")
        case .instagramReel:
            guard ["instagram.com", "www.instagram.com"].contains(host),
                  ["reel", "reels"].contains(path[0]), validCode(path[1]) else { return nil }
            return URL(string: "https://www.instagram.com/reel/\(path[1])/embed/")
        case .tiktok:
            guard ["tiktok.com", "www.tiktok.com", "m.tiktok.com"].contains(host),
                  path.count >= 3, path[0].hasPrefix("@"), path[1] == "video",
                  path[2].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return URL(string: "https://www.tiktok.com/player/v1/\(path[2])?autoplay=1")
        }
    }

    private static func validCode(_ value: Substring) -> Bool {
        value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

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
