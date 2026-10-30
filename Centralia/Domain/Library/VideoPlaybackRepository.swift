import Foundation

struct VideoPlayback: Equatable, Sendable {
    let streamURL: URL?
    let streamReady: Bool
    let expiresAt: Date?
    let embedURL: URL?
    /// Context-aware playback: the backend turned on data saver (mobile data).
    var dataSaver: Bool = false
    /// What to tell the user about it ("You're on mobile data, so…").
    var notice: String? = nil
}

protocol VideoPlaybackRepository {
    func playback(for videoID: UUID) async throws -> VideoPlayback
}
