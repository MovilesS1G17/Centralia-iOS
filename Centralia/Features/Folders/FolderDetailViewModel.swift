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
        Array(Set(videos.flatMap(\.tags))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    var filteredVideos: [VideoItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = videos.filter { video in
            selectedSourceFilter.includes(video)
                && selectedTags.allSatisfy { selectedTag in
                    video.tags.contains { $0.localizedCaseInsensitiveCompare(selectedTag) == .orderedSame }
                }
                && (trimmedQuery.isEmpty || matches(video, query: trimmedQuery))
        }

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
        folderRepository: any FolderRepository
    ) {
        self.folder = folder
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
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
            state = .failed(error.localizedDescription)
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
            failureMessage = error.localizedDescription
        }
    }

    func delete(_ video: VideoItem) async {
        do {
            try await videoRepository.deleteVideo(id: video.id)
            videos.removeAll { $0.id == video.id }
            reconcileSelectedTags()
            recentlyDeletedVideo = video
        } catch {
            failureMessage = error.localizedDescription
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
            failureMessage = error.localizedDescription
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
            failureMessage = error.localizedDescription
            return false
        }
    }

    func deleteFolder() async -> Bool {
        do {
            try await folderRepository.deleteFolder(id: folder.id)
            return true
        } catch {
            failureMessage = error.localizedDescription
            return false
        }
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private func matches(_ video: VideoItem, query: String) -> Bool {
        video.displayTitle.localizedCaseInsensitiveContains(query)
            || video.creator.localizedCaseInsensitiveContains(query)
            || video.tags.contains { $0.localizedCaseInsensitiveContains(query) }
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
