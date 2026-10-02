import Foundation

/// A scalar property value, as accepted by `POST /v1/analytics/events`.
enum AnalyticsValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
}

extension AnalyticsValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// A UI event sent by the app. Names are snake_case (2-64 characters) and at
/// most 20 properties are accepted per event.
struct AnalyticsEvent: Equatable, Sendable {
    let name: String
    let properties: [String: AnalyticsValue]

    init(_ name: String, properties: [String: AnalyticsValue] = [:]) {
        self.name = name
        self.properties = properties
    }
}

enum AnalyticsScreen: String, Sendable {
    case library
    case search
    case videoDetail = "video_detail"
    case folders
    case folderDetail = "folder_detail"
    case saveVideo = "save_video"
}

/// Events the server records by itself (`video_saved`, `video_opened`,
/// `search_performed`, ...) are rejected by the API and must not be sent here.
extension AnalyticsEvent {
    static func screenViewed(_ screen: AnalyticsScreen) -> AnalyticsEvent {
        AnalyticsEvent("screen_viewed", properties: ["screen": .string(screen.rawValue)])
    }

    static func errorShown(screen: AnalyticsScreen, code: String) -> AnalyticsEvent {
        AnalyticsEvent("error_shown", properties: [
            "screen": .string(screen.rawValue),
            "code": .string(code)
        ])
    }

    static func playStarted(videoID: UUID, platform: VideoPlatform) -> AnalyticsEvent {
        AnalyticsEvent("play_started", properties: [
            "video_id": .string(videoID.uuidString.lowercased()),
            "video_platform": .string(platform.rawValue)
        ])
    }

    static func playFailed(videoID: UUID, platform: VideoPlatform, reason: String) -> AnalyticsEvent {
        AnalyticsEvent("play_failed", properties: [
            "video_id": .string(videoID.uuidString.lowercased()),
            "video_platform": .string(platform.rawValue),
            "reason": .string(reason)
        ])
    }

    static func shareTapped(videoID: UUID) -> AnalyticsEvent {
        AnalyticsEvent("share_tapped", properties: [
            "video_id": .string(videoID.uuidString.lowercased())
        ])
    }
}

/// Fire-and-forget: implementations must not block the caller or throw.
protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
}

struct NoOpAnalyticsTracking: AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {}
}
