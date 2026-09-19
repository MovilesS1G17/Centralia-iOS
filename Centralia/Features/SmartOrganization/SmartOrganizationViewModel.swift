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

    private(set) var state: LoadState = .idle
    private(set) var suggestions: [FolderSuggestion] = []
    private(set) var folders: [LibraryFolder] = []
    private(set) var unorganizedCount = 0
    private(set) var isMutating = false
    private(set) var failureMessage: String?

    var selectedSuggestionID: UUID?

    var selectedSuggestion: FolderSuggestion? {
        guard let selectedSuggestionID else { return suggestions.first }
        return suggestions.first { $0.id == selectedSuggestionID } ?? suggestions.first
    }

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        suggestionPipeline: any VideoImportPipeline
    ) {
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.suggestionPipeline = suggestionPipeline
    }

    func load() async {
        guard state == .idle || state.isFailure else { return }
        state = .loading

        do {
            async let loadedVideos = videoRepository.videos()
            async let loadedFolders = folderRepository.folders()
            let (videos, availableFolders) = try await (loadedVideos, loadedFolders)
            let unorganizedVideos = videos.filter { $0.folderID == nil }

            folders = availableFolders
            unorganizedCount = unorganizedVideos.count
            suggestions = await makeSuggestions(
                for: unorganizedVideos,
                folders: availableFolders
            )
            selectedSuggestionID = suggestions.first?.id
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        state = .idle
        await load()
    }

    @discardableResult
    func accept(_ suggestion: FolderSuggestion) async -> Bool {
        await move(suggestion, to: suggestion.folder)
    }

    @discardableResult
    func move(_ suggestion: FolderSuggestion, to folder: LibraryFolder) async -> Bool {
        guard !isMutating else { return false }
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
        guard !isMutating else { return }
        removeSuggestion(id: suggestion.id)
    }

    func apply(_ updatedVideo: VideoItem) {
        guard let index = suggestions.firstIndex(where: { $0.id == updatedVideo.id }) else {
            return
        }

        guard updatedVideo.folderID == nil else {
            unorganizedCount = max(0, unorganizedCount - 1)
            removeSuggestion(id: updatedVideo.id)
            return
        }

        suggestions[index] = FolderSuggestion(
            video: updatedVideo,
            folder: suggestions[index].folder
        )
    }

    func registerDeleted(_ video: VideoItem) {
        guard video.folderID == nil else { return }
        unorganizedCount = max(0, unorganizedCount - 1)
        removeSuggestion(id: video.id)
    }

    func dismissFailure() {
        failureMessage = nil
    }

    private func makeSuggestions(
        for videos: [VideoItem],
        folders: [LibraryFolder]
    ) async -> [FolderSuggestion] {
        var values: [FolderSuggestion] = []

        for video in videos {
            guard !Task.isCancelled else { break }

            let metadata = ImportedVideoMetadata(
                sourceURL: video.sourceURL,
                platform: video.platform,
                creator: video.creator,
                durationSeconds: video.durationSeconds,
                sourceCaption: video.sourceCaption,
                transcript: video.transcript,
                extractedOnScreenText: video.extractedOnScreenText,
                generatedSummary: video.generatedSummary
            )

            guard let folderName = try? await suggestionPipeline.suggestFolder(
                for: metadata,
                tags: video.tags
            ),
            let folder = folders.first(where: {
                $0.name.localizedCaseInsensitiveCompare(folderName) == .orderedSame
            }) else {
                continue
            }

            values.append(FolderSuggestion(video: video, folder: folder))
        }

        return values
    }

    private func removeSuggestion(id: UUID) {
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
