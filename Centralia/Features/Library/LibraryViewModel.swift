import Foundation
import Observation

enum LibrarySourceFilter: CaseIterable, Equatable, Identifiable {
    case all
    case platform(VideoPlatform)

    static let allCases: [LibrarySourceFilter] = [
        .all,
        .platform(.tiktok),
        .platform(.instagramReel),
        .platform(.youtubeShort)
    ]

    var id: String {
        switch self {
        case .all:
            "all"
        case let .platform(platform):
            platform.rawValue
        }
    }

    var displayName: String {
        switch self {
        case .all:
            "All"
        case let .platform(platform):
            platform.filterName
        }
    }

    func includes(_ video: VideoItem) -> Bool {
        switch self {
        case .all:
            true
        case let .platform(platform):
            video.platform == platform
        }
    }
}

@Observable
final class LibraryViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository

    private(set) var state: LoadState = .idle
    private(set) var videos: [VideoItem] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var recentlyDeletedVideo: VideoItem?
    var selectedFilter: LibrarySourceFilter = .all

    var filteredVideos: [VideoItem] {
        videos.filter(selectedFilter.includes)
    }

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository
    ) {
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
    }

    func load() async {
        guard state == .idle || state.isFailure else { return }
        state = .loading

        do {
            videos = try await videoRepository.videos()
            folders = try await folderRepository.folders()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        state = .idle
        await load()
    }

    func delete(_ video: VideoItem) async {
        do {
            try await videoRepository.deleteVideo(id: video.id)
            videos.removeAll { $0.id == video.id }
            recentlyDeletedVideo = video
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func undoDelete() async {
        guard let video = recentlyDeletedVideo else { return }

        do {
            try await videoRepository.restoreVideo(video)
            videos.append(video)
            videos.sort { $0.savedAt > $1.savedAt }
            recentlyDeletedVideo = nil
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func dismissUndo() {
        recentlyDeletedVideo = nil
    }

    func move(_ video: VideoItem, to folderID: UUID?) async {
        do {
            try await videoRepository.moveVideo(id: video.id, to: folderID)

            guard let index = videos.firstIndex(where: { $0.id == video.id }) else {
                return
            }

            videos[index].folderID = folderID
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private extension LibraryViewModel.LoadState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
