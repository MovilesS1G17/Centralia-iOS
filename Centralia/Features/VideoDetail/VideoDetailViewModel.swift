import Foundation
import Observation

/// How a short is shown once playback has been resolved.
enum PlaybackSurface: Equatable {
    case stream(URL)
    case embed(URL)
}

@Observable
final class VideoDetailViewModel {
    enum PlaybackState: Equatable {
        case idle
        case loading
        case ready(PlaybackSurface)
        case failed(String)
    }

    static let playbackUnavailableMessage =
        "This short can't be played here right now. Try opening it in its app."

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let playbackRepository: (any VideoPlaybackRepository)?
    private let analytics: any AnalyticsTracking
    private var hasTrackedScreen = false
    private var fallbackEmbedURL: URL?

    private(set) var video: VideoItem
    private(set) var folders: [LibraryFolder] = []
    private(set) var availableTags: [String] = []
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var failureMessage: String?
    /// Set when the refresh on open fails; the saved copy stays visible.
    private(set) var loadFailureMessage: String?
    private(set) var playbackState: PlaybackState = .idle

    /// False until a playback repository is provided; the screen then keeps
    /// its static preview.
    var supportsPlayback: Bool { playbackRepository != nil }

    var folderName: String? {
        guard let folderID = video.folderID else { return nil }
        return folders.first { $0.id == folderID }?.name
    }

    var folderActionTitle: String {
        video.folderID == nil ? "Choose Folder" : "Change Folder"
    }

    var openActionTitle: String {
        switch video.platform {
        case .tiktok:
            "Open in TikTok"
        case .instagramReel:
            "Open in Instagram"
        case .youtubeShort:
            "Open in YouTube"
        }
    }

    init(
        video: VideoItem,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        playbackRepository: (any VideoPlaybackRepository)? = nil,
        analytics: any AnalyticsTracking = NoOpAnalyticsTracking()
    ) {
        self.video = video
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.playbackRepository = playbackRepository
        self.analytics = analytics
    }

    func startPlayback() async {
        guard let playbackRepository, playbackState != .loading else { return }
        playbackState = .loading
        fallbackEmbedURL = nil

        do {
            let playback = try await playbackRepository.playback(for: video.id)
            let embed = playback.embedURL.flatMap(Self.allowedURL)
            let stream = playback.streamURL.flatMap(Self.allowedURL)
            fallbackEmbedURL = embed

            if let stream {
                playbackState = .ready(.stream(stream))
            } else if let embed {
                playbackState = .ready(.embed(embed))
            } else {
                failPlayback(Self.playbackUnavailableMessage, reason: "playback_unavailable")
                return
            }
            analytics.track(.playStarted(videoID: video.id, platform: video.platform))
        } catch is CancellationError {
            playbackState = .idle
        } catch {
            failPlayback(FeatureError.message(for: error), reason: FeatureError.code(for: error))
        }
    }

    /// The native stream could not be played: use the platform's player if there is one.
    func streamFailed() {
        guard case .ready(.stream) = playbackState else { return }
        analytics.track(.playFailed(videoID: video.id, platform: video.platform, reason: "stream_failed"))
        if let fallbackEmbedURL {
            playbackState = .ready(.embed(fallbackEmbedURL))
        } else {
            playbackState = .failed(Self.playbackUnavailableMessage)
        }
    }

    /// The platform's web player could not be shown.
    func embedFailed() {
        guard case .ready(.embed) = playbackState else { return }
        failPlayback(Self.playbackUnavailableMessage, reason: "embed_failed")
    }

    func stopPlayback() {
        playbackState = .idle
    }

    private func failPlayback(_ message: String, reason: String) {
        playbackState = .failed(message)
        analytics.track(.playFailed(videoID: video.id, platform: video.platform, reason: reason))
    }

    private static func allowedURL(_ url: URL) -> URL? {
        PlaybackURLPolicy.isAllowed(url) ? url : nil
    }

    /// The original link could not be opened in its app.
    func trackPlayFailedOpeningSource() {
        analytics.track(.playFailed(videoID: video.id, platform: video.platform, reason: "open_failed"))
    }

    func trackScreenViewed() {
        guard !hasTrackedScreen else { return }
        hasTrackedScreen = true
        analytics.track(.screenViewed(.videoDetail))
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadFailureMessage = nil
        defer { isLoading = false }

        do {
            async let videosRequest = videoRepository.videos()
            async let foldersRequest = folderRepository.folders()
            let (videos, folders) = try await (videosRequest, foldersRequest)

            self.folders = folders
            if let currentVideo = videos.first(where: { $0.id == video.id }) {
                video = currentVideo
            }
            availableTags = TagCatalog.available(from: videos)
        } catch {
            loadFailureMessage = FeatureError.message(for: error)
            analytics.track(.errorShown(screen: .videoDetail, code: FeatureError.code(for: error)))
        }
    }

    @discardableResult
    func updateTags(_ tags: [String]) async -> Bool {
        await mutate {
            try await videoRepository.updateTags(id: video.id, tags: tags)
            video.tags = TagCatalog.normalize(tags)
            availableTags = TagCatalog.sorted(TagCatalog.normalize(availableTags + video.tags))
        }
    }

    @discardableResult
    func move(to folderID: UUID?) async -> Bool {
        await mutate {
            try await videoRepository.moveVideo(id: video.id, to: folderID)
            video.folderID = folderID
        }
    }

    @discardableResult
    func updateNote(_ note: String?) async -> Bool {
        await mutate {
            let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            try await videoRepository.updateNote(id: video.id, note: trimmedNote)
            video.note = trimmedNote?.isEmpty == false ? trimmedNote : nil
        }
    }

    @discardableResult
    func deleteVideo() async -> Bool {
        await mutate {
            try await videoRepository.deleteVideo(id: video.id)
        }
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private func mutate(_ operation: () async throws -> Void) async -> Bool {
        guard !isMutating else { return false }
        isMutating = true
        failureMessage = nil
        defer { isMutating = false }

        do {
            try await operation()
            return true
        } catch {
            failureMessage = FeatureError.message(for: error)
            analytics.track(.errorShown(screen: .videoDetail, code: FeatureError.code(for: error)))
            return false
        }
    }
}
