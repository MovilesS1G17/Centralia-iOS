import Foundation

enum AnalyticsScreen: String, Sendable {
    case library
    case search
    case videoDetail = "video_detail"
    case folders
    case folderDetail = "folder_detail"
    case saveVideo = "save_video"
}

/// Client UI events, built on the shared `ClientAnalyticsEvent` that
/// `AnalyticsRepository` sends to `POST /v1/analytics/events`. Events the
/// server records by itself (`video_saved`, `search_performed`, ...) are
/// rejected by the API and must not be built here.
extension ClientAnalyticsEvent {
    static func screenViewed(_ screen: AnalyticsScreen) -> ClientAnalyticsEvent {
        event("screen_viewed", ["screen": .text(screen.rawValue)])
    }

    static func errorShown(screen: AnalyticsScreen, code: String) -> ClientAnalyticsEvent {
        event("error_shown", ["screen": .text(screen.rawValue), "code": .text(code)])
    }

    static func playStarted(videoID: UUID, platform: VideoPlatform) -> ClientAnalyticsEvent {
        event("play_started", [
            "video_id": .text(videoID.uuidString.lowercased()),
            "video_platform": .text(platform.rawValue)
        ])
    }

    static func playFailed(videoID: UUID, platform: VideoPlatform, reason: String) -> ClientAnalyticsEvent {
        event("play_failed", [
            "video_id": .text(videoID.uuidString.lowercased()),
            "video_platform": .text(platform.rawValue),
            "reason": .text(reason)
        ])
    }

    static func shareTapped(videoID: UUID) -> ClientAnalyticsEvent {
        event("share_tapped", ["video_id": .text(videoID.uuidString.lowercased())])
    }

    private static func event(_ name: String, _ properties: [String: AnalyticsValue]) -> ClientAnalyticsEvent {
        ClientAnalyticsEvent(name: name, occurredAt: Date(), properties: properties)
    }
}

/// What the screens depend on. Fire-and-forget: implementations must not
/// block the caller or throw.
protocol AnalyticsTracking: Sendable {
    func track(_ event: ClientAnalyticsEvent)
}

struct NoOpAnalyticsTracking: AnalyticsTracking {
    func track(_ event: ClientAnalyticsEvent) {}
}
