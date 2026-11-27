import Foundation
import Observation

struct FolderSuggestion: Identifiable, Equatable {
    let video: VideoItem
    let folder: LibraryFolder

    var id: UUID { video.id }
}

@Observable
final class SmartOrganizationViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let suggestionPipeline: any VideoImportPipeline
    private let cache: FolderSuggestionCache
    private let accountID: UUID
    private var skippedIDs: Set<UUID> = []
    private var currentLoadID: UUID?

    private(set) var state: LoadState = .idle
    private(set) var suggestions: [FolderSuggestion] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var unorganizedCount = 0
    private(set) var isMutating = false
    private(set) var isRefreshing = false
    private(set) var cachedSuggestionIDs: Set<UUID> = []
    private(set) var connectionNeeded: Set<UUID> = []
    private(set) var failedLookups: Set<UUID> = []
    private(set) var refreshFailed = false
    private(set) var failureMessage: String?

    var selectedSuggestionID: UUID?
    var hasSkipped: Bool { !skippedIDs.isEmpty }

    var selectedSuggestion: FolderSuggestion? {
        guard let selectedSuggestionID else { return suggestions.first }
        return suggestions.first { $0.id == selectedSuggestionID } ?? suggestions.first
    }

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        suggestionPipeline: any VideoImportPipeline,
        cache: FolderSuggestionCache,
        accountID: UUID
    ) {
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.suggestionPipeline = suggestionPipeline
        self.cache = cache
        self.accountID = accountID
    }

    func load(isOnline: () -> Bool = { true }) async {
        guard state == .idle || state.isFailure else { return }
        await refresh(isOnline: isOnline, bypassCache: false)
    }

    func refresh(isOnline: () -> Bool, bypassCache: Bool = true) async {
        guard !isMutating else { return }
        let loadID = UUID()
        currentLoadID = loadID
        let hadResults = state == .loaded
        refreshFailed = false
        isRefreshing = hadResults
        if !hadResults { state = .loading }
        defer {
            if currentLoadID == loadID {
                isRefreshing = false
                if state == .loading { state = .idle }
            }
        }

        do {
            async let loadedVideos = videoRepository.videos()
            async let loadedFolders = folderRepository.folders()
            let (videos, availableFolders) = try await (loadedVideos, loadedFolders)
            let unorganizedVideos = videos.filter { $0.folderID == nil }
            let candidates = unorganizedVideos.filter { !skippedIDs.contains($0.id) }
            let lookup = await cache.lookup(for: accountID, videos: candidates, folders: availableFolders)
            try Task.checkCancellation()
            guard currentLoadID == loadID else { return }

            let report = try await makeSuggestions(
                for: candidates, folders: availableFolders, lookup: lookup,
                isOnline: isOnline, bypassCache: bypassCache
            )
            try Task.checkCancellation()
            guard currentLoadID == loadID else { return }
            await cache.save(report.updates, from: lookup)
            try Task.checkCancellation()
            guard currentLoadID == loadID else { return }

            let selectedID = selectedSuggestionID
            folders = availableFolders
            unorganizedCount = unorganizedVideos.count
            suggestions = report.suggestions
            cachedSuggestionIDs = report.cachedIDs
            connectionNeeded = report.connectionNeeded
            failedLookups = report.failedLookups
            selectedSuggestionID = suggestions.first(where: { $0.id == selectedID })?.id ?? suggestions.first?.id
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard currentLoadID == loadID, !Task.isCancelled else { return }
            if hadResults { refreshFailed = true }
            else { state = .failed(FeatureError.message(for: error)) }
        }
    }

    /// A changed inventory invalidates prior suggestions immediately. Icon-only
    /// updates retain the recommendation and use the latest folder presentation.
    func updateFolders(_ updated: [LibraryFolder]) -> Bool {
        guard state == .loaded, updated != folders else { return false }
        let inventoryChanged = FolderSuggestionCache.FolderIdentity.inventory(updated)
            != FolderSuggestionCache.FolderIdentity.inventory(folders)
        folders = updated
        if inventoryChanged {
            suggestions = []
            cachedSuggestionIDs = []
            connectionNeeded = []
            failedLookups = []
            return true
        }
        suggestions = suggestions.map { suggestion in
            let folder = updated.first { $0.id == suggestion.folder.id } ?? suggestion.folder
            return FolderSuggestion(video: suggestion.video, folder: folder)
        }
        return false
    }

    @discardableResult
    func accept(_ suggestion: FolderSuggestion) async -> Bool {
        await move(suggestion, to: suggestion.folder)
    }

    @discardableResult
    func move(_ suggestion: FolderSuggestion, to folder: LibraryFolder) async -> Bool {
        guard !isMutating, !isRefreshing,
              suggestions.contains(where: { $0.id == suggestion.id }),
              folders.contains(where: { $0.id == folder.id }) else { return false }
        isMutating = true
        failureMessage = nil
        defer { isMutating = false }

        do {
            try await videoRepository.moveVideo(id: suggestion.video.id, to: folder.id)
            unorganizedCount = max(0, unorganizedCount - 1)
            removeSuggestion(id: suggestion.id)
            return true
        } catch {
            failureMessage = error.localizedDescription
            return false
        }
    }

    func skip(_ suggestion: FolderSuggestion) {
        guard !isMutating, !isRefreshing else { return }
        skippedIDs.insert(suggestion.id)
        removeSuggestion(id: suggestion.id)
    }

    @discardableResult
    func apply(_ updatedVideo: VideoItem) -> Bool {
        guard let index = suggestions.firstIndex(where: { $0.id == updatedVideo.id }) else {
            return false
        }

        guard updatedVideo.folderID == nil else {
            unorganizedCount = max(0, unorganizedCount - 1)
            removeSuggestion(id: updatedVideo.id)
            return false
        }

        if FolderSuggestionCache.Input(suggestions[index].video) != FolderSuggestionCache.Input(updatedVideo) {
            removeSuggestion(id: updatedVideo.id)
            return true
        }

        suggestions[index] = FolderSuggestion(
            video: updatedVideo,
            folder: suggestions[index].folder
        )
        return false
    }

    func registerDeleted(_ video: VideoItem) {
        guard video.folderID == nil else { return }
        unorganizedCount = max(0, unorganizedCount - 1)
        removeSuggestion(id: video.id)
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private struct SuggestionReport {
        var suggestions: [FolderSuggestion] = []
        var cachedIDs: Set<UUID> = []
        var connectionNeeded: Set<UUID> = []
        var failedLookups: Set<UUID> = []
        var updates: [FolderSuggestionCache.Update] = []
    }

    private func makeSuggestions(
        for videos: [VideoItem],
        folders: [LibraryFolder],
        lookup: FolderSuggestionCache.Lookup,
        isOnline: () -> Bool,
        bypassCache: Bool
    ) async throws -> SuggestionReport {
        var report = SuggestionReport()
        var connectionLost = false
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

        for video in videos {
            try Task.checkCancellation()
            let cachedFolder = lookup.folderIDs[video.id].flatMap { foldersByID[$0] }

            if !connectionLost, isOnline(), bypassCache || cachedFolder == nil {
                do {
                    let input = FolderSuggestionCache.Input(video)
                    let name = try await suggestionPipeline.suggestFolder(for: input.metadata, tags: input.tags)
                    let folder = name.flatMap { name in
                        folders.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
                    }
                    report.updates.append(.init(videoID: video.id, folderID: folder?.id))
                    if let folder { report.suggestions.append(FolderSuggestion(video: video, folder: folder)) }
                    continue
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if APIClientError.isOffline(error) || (error as? URLError)?.code == .notConnectedToInternet {
                        connectionLost = true
                    } else {
                        report.failedLookups.insert(video.id)
                    }
                }
            }

            if let cachedFolder {
                report.suggestions.append(FolderSuggestion(video: video, folder: cachedFolder))
                report.cachedIDs.insert(video.id)
            } else if connectionLost || !isOnline() {
                report.connectionNeeded.insert(video.id)
            }
        }
        return report
    }

    private func removeSuggestion(id: UUID) {
        cachedSuggestionIDs.remove(id)
        connectionNeeded.remove(id)
        failedLookups.remove(id)
        guard let removedIndex = suggestions.firstIndex(where: { $0.id == id }) else {
            return
        }

        suggestions.remove(at: removedIndex)

        guard !suggestions.isEmpty else {
            selectedSuggestionID = nil
            return
        }

        let nextIndex = min(removedIndex, suggestions.count - 1)
        selectedSuggestionID = suggestions[nextIndex].id
    }
}

private extension SmartOrganizationViewModel.LoadState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
