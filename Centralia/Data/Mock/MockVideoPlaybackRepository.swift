import Foundation

struct MockVideoPlaybackRepository: VideoPlaybackRepository {
    let videoRepository: any VideoItemRepository

    func playback(for videoID: UUID) async throws -> VideoPlayback {
        guard let video = try await videoRepository.videos().first(where: { $0.id == videoID }) else {
            throw APIClientError.server(
                status: 404, code: "video_not_found",
                detail: "This short is no longer in your library.",
                email: nil, retryAfter: nil
            )
        }
        return VideoPlayback(
            streamURL: nil, streamReady: false,
            expiresAt: nil, embedURL: video.sourceURL
        )
    }
}
