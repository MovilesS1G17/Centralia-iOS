import Foundation
import Observation

enum FolderSort: String, CaseIterable, Identifiable {
    case dateSaved
    case alphabetical

    var id: Self { self }

    var title: String {
        switch self {
        case .dateSaved: "Date Saved"
        case .alphabetical: "Alphabetical"
        }
    }
}

@Observable
final class FolderDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let analytics: any AnalyticsTracking
    private var hasTrackedScreen = false

    private(set) var state: LoadState = .idle
    private(set) var folder: LibraryFolder
    private(set) var videos: [VideoItem] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var recentlyDeletedVideo: VideoItem?
    private(set) var failureMessage: String?

    var query = ""
    var selectedSourceFilter: LibrarySourceFilter = .all
    var selectedTags: Set<String> = []
    var sort: FolderSort = .dateSaved

    var availableTags: [String] {
        TagCatalog.available(from: videos)
    }

    var filteredVideos: [VideoItem] {
        var criteria = VideoSearchCriteria(text: query, tags: selectedTags)
        if case let .platform(platform) = selectedSourceFilter {
            criteria.platform = platform
        }
        let filtered = VideoSearch.filter(videos, criteria: criteria)

        switch sort {
        case .dateSaved:
            return filtered.sorted { $0.savedAt > $1.savedAt }
        case .alphabetical:
            return filtered.sorted {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
        }
    }

    init(
        folder: LibraryFolder,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        analytics: any AnalyticsTracking = NoOpAnalyticsTracking()
    ) {
        self.folder = folder
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.analytics = analytics
    }

    func trackScreenViewed() {
        guard !hasTrackedScreen else { return }
        hasTrackedScreen = true
        analytics.track(.screenViewed(.folderDetail))
    }

    private func presentFailure(_ error: Error) {
        failureMessage = FeatureError.report(error, screen: .folderDetail, analytics: analytics)
    }

    func load() async {
        guard state == .idle || state.isFailure else { return }
        state = .loading

        do {
            async let loadedVideos = videoRepository.videos()
            async let loadedFolders = folderRepository.folders()
            videos = try await loadedVideos.filter { $0.folderID == folder.id }
            folders = try await loadedFolders
            reconcileSelectedTags()
            state = .loaded
        } catch {
            state = .failed(FeatureError.message(for: error))
            analytics.track(.errorShown(screen: .folderDetail, code: FeatureError.code(for: error)))
        }
    }

    func retry() async {
        state = .idle
        await load()
    }

    func move(_ video: VideoItem, to folderID: UUID?) async {
        do {
            try await videoRepository.moveVideo(id: video.id, to: folderID)
            videos.removeAll { $0.id == video.id }
            reconcileSelectedTags()
        } catch {
            presentFailure(error)
        }
    }

    func delete(_ video: VideoItem) async {
        do {
            try await videoRepository.deleteVideo(id: video.id)
            videos.removeAll { $0.id == video.id }
            reconcileSelectedTags()
            recentlyDeletedVideo = video
        } catch {
            presentFailure(error)
        }
    }

    func undoDelete() async {
        guard let video = recentlyDeletedVideo else { return }

        do {
            try await videoRepository.restoreVideo(video)
            videos.append(video)
            reconcileSelectedTags()
            recentlyDeletedVideo = nil
        } catch {
            presentFailure(error)
        }
    }

    func dismissUndo() {
        recentlyDeletedVideo = nil
    }

    func apply(_ video: VideoItem) {
        if video.folderID == folder.id {
            if let index = videos.firstIndex(where: { $0.id == video.id }) {
                videos[index] = video
            } else {
                videos.append(video)
            }
        } else {
            videos.removeAll { $0.id == video.id }
        }
        reconcileSelectedTags()
    }

    func registerDeleted(_ video: VideoItem) {
        videos.removeAll { $0.id == video.id }
        reconcileSelectedTags()
        recentlyDeletedVideo = video
    }

    func renameFolder(to name: String) async -> Bool {
        do {
            folder = try await folderRepository.renameFolder(id: folder.id, to: name)
            failureMessage = nil
            return true
        } catch {
            presentFailure(error)
            return false
        }
    }

    func deleteFolder() async -> Bool {
        do {
            try await folderRepository.deleteFolder(id: folder.id)
            return true
        } catch {
            // Already removed elsewhere: the goal of the action is met.
            if FeatureError.code(for: error) == "folder_not_found" {
                return true
            }
            presentFailure(error)
            return false
        }
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private func reconcileSelectedTags() {
        selectedTags.formIntersection(availableTags)
    }
}

private extension FolderDetailViewModel.LoadState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
