import Foundation

actor JSONLibraryExportService: LibraryExportService {
    private struct ExportDocument: Codable, Sendable {
        let schemaVersion: Int
        let exportedAt: Date
        let profile: UserProfile
        let notificationPreferences: NotificationPreferences
        let folders: [LibraryFolder]
        let videos: [VideoItem]
    }

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let userRepository: any UserRepository
    private let fileManager: FileManager

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        userRepository: any UserRepository,
        fileManager: FileManager = .default
    ) {
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.userRepository = userRepository
        self.fileManager = fileManager
    }

    func exportLibrary(for profile: UserProfile) async throws -> URL {
        async let loadedVideos = videoRepository.videos()
        async let loadedFolders = folderRepository.folders()
        async let loadedPreferences = userRepository.notificationPreferences(for: profile.id)

        let (videos, folders, preferences) = try await (
            loadedVideos,
            loadedFolders,
            loadedPreferences
        )

        let document = ExportDocument(
            schemaVersion: 1,
            exportedAt: Date(),
            profile: profile,
            notificationPreferences: preferences,
            folders: folders,
            videos: videos
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw LibraryExportError.unableToEncode(error)
        }

        let exportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("Centralia-Exports", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: exportDirectory,
                withIntermediateDirectories: true
            )
            let fileURL = exportDirectory.appendingPathComponent(
                "Centralia-Library-\(UUID().uuidString).json"
            )
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            throw LibraryExportError.unableToWrite(error)
        }
    }

}
