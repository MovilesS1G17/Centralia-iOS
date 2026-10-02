import Foundation
import Observation

@Observable
final class SearchViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let searchHistoryRepository: any SearchHistoryRepository
    private let analytics: any AnalyticsTracking
    private var hasTrackedScreen = false

    private(set) var state: LoadState = .idle
    private(set) var failureMessage: String?
    private(set) var videos: [VideoItem] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var recentSearches: [String] = []
    private(set) var recentlyDeletedVideo: VideoItem?

    var query = ""
    var selectedPlatform: VideoPlatform?
    var selectedCreator: String?
    var selectedFolder: SearchFolderFilter = .all
    var selectedTags: Set<String> = []

    var criteria: VideoSearchCriteria {
        VideoSearchCriteria(
            text: query,
            platform: selectedPlatform,
            creator: selectedCreator,
            folder: selectedFolder,
            tags: selectedTags
        )
    }

    var filteredVideos: [VideoItem] {
        VideoSearch.filter(
            videos,
            criteria: criteria,
            folderNames: Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.name) })
        )
    }

    var availableCreators: [String] {
        Array(Set(videos.map(\.creator))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var availableTags: [String] {
        TagCatalog.available(from: videos)
    }

    var hasActiveFilters: Bool {
        selectedPlatform != nil
            || selectedCreator != nil
            || selectedFolder != .all
            || !selectedTags.isEmpty
    }

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        searchHistoryRepository: any SearchHistoryRepository,
        analytics: any AnalyticsTracking = NoOpAnalyticsTracking()
    ) {
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.searchHistoryRepository = searchHistoryRepository
        self.analytics = analytics
    }

    func trackScreenViewed() {
        guard !hasTrackedScreen else { return }
        hasTrackedScreen = true
        analytics.track(.screenViewed(.search))
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private func presentFailure(_ error: Error) {
        failureMessage = FeatureError.report(error, screen: .search, analytics: analytics)
    }

    func load() async {
        guard state == .idle || state.isFailure else { return }
        state = .loading

        do {
            videos = try await videoRepository.videos()
            folders = try await folderRepository.folders()
            state = .loaded
        } catch {
            state = .failed(FeatureError.message(for: error))
            analytics.track(.errorShown(screen: .search, code: FeatureError.code(for: error)))
            return
        }

        await loadRecentSearches()
    }

    func retry() async {
        state = .idle
        await load()
    }

    /// The history is a convenience: when it can't be read the screen still works.
    func loadRecentSearches() async {
        recentSearches = (try? await searchHistoryRepository.recentSearches()) ?? []
    }

    func submitSearch() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        // The backend records `search_performed` itself when the query is stored.
        try? await searchHistoryRepository.recordSearch(trimmedQuery)
        await loadRecentSearches()
    }

    func selectRecentSearch(_ search: String) async {
        query = search
        await submitSearch()
    }

    func clearRecentSearches() async {
        do {
            try await searchHistoryRepository.clearSearchHistory()
            recentSearches = []
        } catch {
            presentFailure(error)
        }
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func clearFilters() {
        selectedPlatform = nil
        selectedCreator = nil
        selectedFolder = .all
        selectedTags.removeAll()
    }

    func clearSearch() {
        query = ""
        clearFilters()
    }

    func delete(_ video: VideoItem) async {
        do {
            try await videoRepository.deleteVideo(id: video.id)
            videos.removeAll { $0.id == video.id }
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
            videos.sort { $0.savedAt > $1.savedAt }
            recentlyDeletedVideo = nil
        } catch {
            presentFailure(error)
        }
    }

    func dismissUndo() {
        recentlyDeletedVideo = nil
    }

    func apply(_ video: VideoItem) {
        guard let index = videos.firstIndex(where: { $0.id == video.id }) else { return }
        videos[index] = video
    }

    func registerDeleted(_ video: VideoItem) {
        videos.removeAll { $0.id == video.id }
        recentlyDeletedVideo = video
    }

    func move(_ video: VideoItem, to folderID: UUID?) async {
        do {
            try await videoRepository.moveVideo(id: video.id, to: folderID)

            guard let index = videos.firstIndex(where: { $0.id == video.id }) else {
                return
            }

            videos[index].folderID = folderID
        } catch {
            presentFailure(error)
        }
    }

    func folderName(for folderID: UUID?) -> String? {
        guard let folderID else { return nil }
        return folders.first { $0.id == folderID }?.name
    }
}

private extension SearchViewModel.LoadState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
