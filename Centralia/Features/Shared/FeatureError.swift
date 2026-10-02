import Foundation

/// An error that carries the backend's stable `code`.
protocol CodedError: Error {
    var code: String { get }
}

/// Turns any error into something safe to show and something safe to log.
enum FeatureError {
    static let genericMessage = "Something went wrong. Please try again."
    static let offlineMessage = "We couldn’t reach Centralia. Check your connection and try again."

    /// The backend's `detail` when the error carries one, otherwise a generic sentence.
    static func message(for error: Error) -> String {
        if error is URLError { return offlineMessage }
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return description
        }
        return genericMessage
    }

    /// Builds the user-facing message and records `error_shown` for the screen.
    static func report(_ error: Error, screen: AnalyticsScreen, analytics: any AnalyticsTracking) -> String {
        analytics.track(.errorShown(screen: screen, code: code(for: error)))
        return message(for: error)
    }

    /// Errors that repeating the same request cannot fix: the link, the folder
    /// or the data itself is the problem. Everything else (network, server,
    /// unknown) is worth another attempt.
    private static let permanentCodes: Set<String> = [
        "duplicate_video", "video_not_found", "folder_not_found",
        "folder_name_empty", "folder_name_duplicate", "validation_error",
        "invalid_url", "unsupported_source", "unsupported_youtube_video",
        "unsupported_instagram_post", "not_authenticated"
    ]

    static func isRetryable(_ error: Error) -> Bool {
        !permanentCodes.contains(code(for: error))
    }

    /// The V3 error code when it can be determined, `unknown` otherwise.
    static func code(for error: Error) -> String {
        if let coded = error as? CodedError { return coded.code }
        if error is URLError { return "network_unavailable" }

        switch error {
        case let error as VideoItemRepositoryError:
            switch error {
            case .duplicateVideo: return "duplicate_video"
            }
        case let error as FolderRepositoryError:
            switch error {
            case .emptyName: return "folder_name_empty"
            case .duplicateName: return "folder_name_duplicate"
            case .folderNotFound: return "folder_not_found"
            }
        case let error as VideoImportError:
            switch error {
            case .invalidURL: return "invalid_url"
            case .unsupportedSource: return "unsupported_source"
            case .unsupportedYouTubeVideo: return "unsupported_youtube_video"
            case .unsupportedInstagramPost: return "unsupported_instagram_post"
            }
        default:
            return "unknown"
        }
    }
}
