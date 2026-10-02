import Foundation
import Observation

enum SearchFolderFilter: Equatable, Sendable {
    case all
    case unorganized
    case folder(UUID)
}

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
    private let searchRepository: any SearchRepository
    private let searchHistoryRepository: any SearchHistoryRepository

    private(set) var state: LoadState = .idle
    private(set) var videos: [VideoItem] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var recentSearches: [String] = []
    private(set) var recentlyDeletedVideo: VideoItem?

    var query = ""
    var selectedPlatform: VideoPlatform?
    var selectedCreator: String?
    var selectedFolder: SearchFolderFilter = .all
    var selectedTags: Set<String> = []

    private var searchTask: Task<Void, Never>?
    private var hasEverLoaded = false

    var filteredVideos: [VideoItem] {
        let terms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return videos.filter { video in
            guard selectedPlatform == nil || video.platform == selectedPlatform else {
                return false
            }

            guard selectedCreator == nil || video.creator == selectedCreator else {
                return false
            }

            switch selectedFolder {
            case .all:
                break
            case .unorganized where video.folderID != nil:
                return false
            case .unorganized:
                break
            case let .folder(folderID) where video.folderID != folderID:
                return false
            case .folder:
                break
            }

            guard selectedTags.isSubset(of: Set(video.tags)) else {
                return false
            }

            guard !terms.isEmpty else { return true }

            let searchableValues = [
                video.displayTitle,
                video.creator,
                folderName(for: video.folderID) ?? ""
            ] + video.tags

            return terms.allSatisfy { term in
                searchableValues.contains { value in
                    value.localizedStandardContains(term)
                }
            }
        }
    }

    var availableCreators: [String] {
        Array(Set(videos.map(\.creator))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var availableTags: [String] {
        Array(Set(videos.flatMap(\.tags))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
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
        searchRepository: any SearchRepository,
        searchHistoryRepository: any SearchHistoryRepository
    ) {
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.searchRepository = searchRepository
        self.searchHistoryRepository = searchHistoryRepository
    }

    func load() async {
        guard state == .idle || state.isFailure else { return }
        state = .loading

        do {
            videos = try await videoRepository.videos()
            folders = try await folderRepository.folders()
            recentSearches = try await searchHistoryRepository.recentSearches()
            state = .loaded
            hasEverLoaded = true
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Retries whatever last failed: the initial load if it never
    /// succeeded, or the last search otherwise (so "Try Again" after a
    /// failed filtered search retries that search, not a full reload).
    func retry() async {
        guard state.isFailure else { return }
        if hasEverLoaded {
            performSearch()
        } else {
            state = .idle
            await load()
        }
    }

    /// Runs a real backend search (`GET /videos`, Specification-filtered)
    /// against whatever query/filters are currently active, measures the
    /// client-perceived latency with a monotonic clock, and — only when at
    /// least one filter or query term is active — reports it as
    /// `search_completed` without blocking the UI. The server-filtered
    /// result becomes the new `videos`; `filteredVideos` still narrows
    /// further client-side for things the backend doesn't support (multiple
    /// tags, multi-term AND matching, "unorganized", matching tags/folder
    /// name by text).
    func performSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.runSearch()
        }
    }

    private var singleTermServerQuery: String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        return trimmed
    }

    private var serverFolderID: UUID? {
        guard case let .folder(folderID) = selectedFolder else { return nil }
        return folderID
    }

    private var serverTag: String? {
        selectedTags.count == 1 ? selectedTags.first : nil
    }

    private var activeFilterCount: Int {
        var count = 0
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if selectedPlatform != nil { count += 1 }
        if selectedCreator != nil { count += 1 }
        if selectedFolder != .all { count += 1 }
        if !selectedTags.isEmpty { count += 1 }
        return count
    }

    private func runSearch() async {
        state = .loading
        let clock = ContinuousClock()
        let start = clock.now

        do {
            let result = try await searchRepository.search(
                query: singleTermServerQuery,
                platform: selectedPlatform,
                creator: selectedCreator,
                folderID: serverFolderID,
                tag: serverTag,
                limit: nil,
                offset: 0
            )
            guard !Task.isCancelled else { return }
            videos = result.videos
            state = .loaded

            let filterCount = activeFilterCount
            if filterCount > 0 {
                let elapsed = start.duration(to: clock.now)
                let durationMs = Int(elapsed.components.seconds) * 1000
                    + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
                searchRepository.reportSearchCompleted(
                    durationMs: durationMs,
                    resultCount: result.totalCount,
                    filterCount: filterCount
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func submitSearch() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        do {
            try await searchHistoryRepository.recordSearch(trimmedQuery)
            recentSearches = try await searchHistoryRepository.recentSearches()
        } catch {
            state = .failed(error.localizedDescription)
        }

        performSearch()
    }

    func selectPlatform(_ platform: VideoPlatform?) {
        selectedPlatform = platform
        performSearch()
    }

    func selectCreator(_ creator: String?) {
        selectedCreator = creator
        performSearch()
    }

    func selectFolder(_ folder: SearchFolderFilter) {
        selectedFolder = folder
        performSearch()
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
            state = .failed(error.localizedDescription)
        }
    }

    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
        performSearch()
    }

    func clearFilters() {
        selectedPlatform = nil
        selectedCreator = nil
        selectedFolder = .all
        selectedTags.removeAll()
        performSearch()
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
            state = .failed(error.localizedDescription)
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
