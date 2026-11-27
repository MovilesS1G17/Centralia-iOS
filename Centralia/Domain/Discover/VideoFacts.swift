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
