import Foundation
import Observation

@Observable
final class FoldersViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository

    private(set) var state: LoadState = .idle
    private(set) var folders: [LibraryFolder] = []
    private(set) var videos: [VideoItem] = []
    private(set) var failureMessage: String?

    var query = ""

    var filteredFolders: [LibraryFolder] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return folders }

        return folders.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var unorganizedCount: Int {
        videos.count { $0.folderID == nil }
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
            async let loadedVideos = videoRepository.videos()
            async let loadedFolders = folderRepository.folders()
            videos = try await loadedVideos
            folders = try await loadedFolders
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        state = .idle
        await load()
    }

    func createFolder(named name: String, symbol: FolderSymbol) async -> LibraryFolder? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            failureMessage = FolderRepositoryError.emptyName.localizedDescription
            return nil
        }

        do {
            let folder = try await folderRepository.createFolder(
                named: name,
                symbolName: symbol.rawValue
            )
            folders.append(folder)
            folders.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            failureMessage = nil
            return folder
        } catch {
            failureMessage = error.localizedDescription
            return nil
        }
    }

    func itemCount(in folder: LibraryFolder) -> Int {
        videos.count { $0.folderID == folder.id }
    }

    func applyFolderChange() async {
        state = .idle
        await load()
    }

    func dismissFailure() {
        failureMessage = nil
    }
}

private extension FoldersViewModel.LoadState {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
