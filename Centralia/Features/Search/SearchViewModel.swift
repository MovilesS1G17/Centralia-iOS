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
        searchHistoryRepository: any SearchHistoryRepository
    ) {
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
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
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        state = .idle
        await load()
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
