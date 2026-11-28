import Foundation

/// The parts of a `VideoItem` the Sprint 4 features compute with, copied on
/// the main actor into a plain `Sendable` value. The heavy work (Rediscover
/// scoring, grouping creators, Insights) then runs off the main thread on
/// these copies, and the results are matched back to the `VideoItem`s by id.
nonisolated struct VideoFacts: Equatable, Hashable, Sendable {
    let id: UUID
    let savedAt: Date
    let creator: String
    let platformRaw: String
    let folderID: UUID?
    let tags: [String]

    init(id: UUID, savedAt: Date, creator: String, platformRaw: String, folderID: UUID?, tags: [String]) {
        self.id = id
        self.savedAt = savedAt
        self.creator = creator
        self.platformRaw = platformRaw
        self.folderID = folderID
        self.tags = tags
    }

    @MainActor
    init(_ video: VideoItem) {
        self.init(
            id: video.id,
            savedAt: video.savedAt,
            creator: video.creator,
            platformRaw: video.platform.rawValue,
            folderID: video.folderID,
            tags: video.tags
        )
    }
}

/// The Sprint 4 feature events (BQ11-15), sent through `AnalyticsTracking`.
extension ClientAnalyticsEvent {
    static func rediscoverViewed(shown: Int) -> ClientAnalyticsEvent {
        sprint4("rediscover_viewed", ["shown": .integer(shown)])
    }

    static func rediscoverOpened(videoID: UUID, daysSinceSave: Int) -> ClientAnalyticsEvent {
        sprint4("rediscover_opened", [
            "video_id": .text(videoID.uuidString.lowercased()),
            "days_since_save": .integer(daysSinceSave)
        ])
    }

    static func watchLaterAdded(videoID: UUID) -> ClientAnalyticsEvent {
        sprint4("watch_later_added", ["video_id": .text(videoID.uuidString.lowercased())])
    }

    static func watchLaterOpened(videoID: UUID, hoursInQueue: Double) -> ClientAnalyticsEvent {
        sprint4("watch_later_opened", [
            "video_id": .text(videoID.uuidString.lowercased()),
            "hours_in_queue": .decimal(hoursInQueue)
        ])
    }

    static func trendsLoaded(source: TrendsSource, durationMs: Double, stale: Bool, windowDays: Int) -> ClientAnalyticsEvent {
        sprint4("trends_loaded", [
            "source": .text(source.rawValue),
            "duration_ms": .decimal(durationMs),
            "stale": .boolean(stale),
            "window_days": .integer(windowDays)
        ])
    }

    static func creatorsViewed(creators: Int) -> ClientAnalyticsEvent {
        sprint4("creators_viewed", ["creators": .integer(creators)])
    }

    static func insightsViewed(weeks: Int) -> ClientAnalyticsEvent {
        sprint4("insights_viewed", ["weeks": .integer(weeks)])
    }

    private static func sprint4(_ name: String, _ properties: [String: AnalyticsValue]) -> ClientAnalyticsEvent {
        ClientAnalyticsEvent(name: name, occurredAt: Date(), properties: properties)
    }
}
