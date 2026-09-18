import Foundation
import Observation

@Observable
final class VideoDetailViewModel {
    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository

    private(set) var video: VideoItem
    private(set) var folders: [LibraryFolder] = []
    private(set) var availableTags: [String] = []
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var failureMessage: String?

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
        folderRepository: any FolderRepository
    ) {
        self.video = video
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        failureMessage = nil
        defer { isLoading = false }

        do {
            async let videosRequest = videoRepository.videos()
            async let foldersRequest = folderRepository.folders()
            let (videos, folders) = try await (videosRequest, foldersRequest)

            self.folders = folders
            if let currentVideo = videos.first(where: { $0.id == video.id }) {
                video = currentVideo
            }
            availableTags = Self.sortedTags(from: videos)
        } catch {
            failureMessage = error.localizedDescription
        }
    }

    @discardableResult
    func updateTags(_ tags: [String]) async -> Bool {
        await mutate {
            try await videoRepository.updateTags(id: video.id, tags: tags)
            video.tags = Self.normalizedTags(tags)
            availableTags = Self.sortedTags(including: availableTags + video.tags)
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
            failureMessage = error.localizedDescription
            return false
        }
    }

    private static func sortedTags(from videos: [VideoItem]) -> [String] {
        sortedTags(including: videos.flatMap(\.tags))
    }

    private static func sortedTags(including tags: [String]) -> [String] {
        normalizedTags(tags).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var normalized: [String] = []

        for value in tags {
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty,
                  !normalized.contains(where: {
                      $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
                  }) else {
                continue
            }
            normalized.append(tag)
        }

        return normalized
    }
}
