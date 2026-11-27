import Foundation

/// What the Save screen shows when a pasted link can't be saved
/// (TA feedback: "when saving an inadmissible link, make it more telling").
///
/// The API explains every rejected link in two parts: a short `title` that
/// says what is wrong ("This TikTok link isn't a video") and a `message` that
/// says how to get a link that works. Older servers send no title, and some
/// failures never reach the server, so this picks a sensible title for those.
/// Same rules as `LinkProblem.kt` on Android.
nonisolated struct LinkProblem: Equatable, Sendable {
    static let defaultTitle = "This link can't be saved"
    static let offlineTitle = "Can't check this link right now"
    static let offlineMessage =
        "You're offline. Checking a link needs a connection. Try again when you're back online."

    let title: String
    let message: String

    static func from(code: String?, title: String?, detail: String?) -> LinkProblem {
        if code == "unreachable" || code == "network_unavailable" || code == "offline" {
            return LinkProblem(title: offlineTitle, message: offlineMessage)
        }
        let fallbackTitle: String
        switch code {
        case "invalid_url": fallbackTitle = "That isn't a complete link"
        case "unsupported_youtube_video": fallbackTitle = "This is a regular YouTube video"
        case "unsupported_instagram_post": fallbackTitle = "This is an Instagram post, not a Reel"
        case "duplicate_video": fallbackTitle = "Already in your library"
        default: fallbackTitle = defaultTitle
        }
        let message: String
        if let detail, !detail.trimmingCharacters(in: .whitespaces).isEmpty {
            message = detail
        } else {
            message = "Centralia saves TikTok videos, Instagram Reels and YouTube Shorts. "
                + "Open the short in its app, tap Share → Copy link, and paste it here."
        }
        let headline = title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return LinkProblem(title: headline ?? fallbackTitle, message: message)
    }

    /// Builds the problem from any error the import pipeline throws.
    static func from(error: Error, message: String) -> LinkProblem {
        if let apiError = error as? APIClientError {
            switch apiError {
            case let .server(_, code, detail, _, _, title):
                return from(code: code, title: title, detail: detail)
            case .networkUnavailable:
                return from(code: "network_unavailable", title: nil, detail: nil)
            default:
                break
            }
        }
        return from(code: nil, title: nil, detail: message)
    }
}
