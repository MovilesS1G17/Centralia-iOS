import Foundation

struct VideoPlayback: Equatable, Sendable {
    let streamURL: URL?
    let streamReady: Bool
    let expiresAt: Date?
    let embedURL: URL?
}

protocol VideoPlaybackRepository {
    func playback(for videoID: UUID) async throws -> VideoPlayback
}
