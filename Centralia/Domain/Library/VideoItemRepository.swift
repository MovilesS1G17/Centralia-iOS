import Foundation

protocol VideoItemRepository {
    func videos() async throws -> [VideoItem]
    func saveVideo(_ video: VideoItem) async throws
    func deleteVideo(id: UUID) async throws
    func restoreVideo(_ video: VideoItem) async throws
    func moveVideo(id: UUID, to folderID: UUID?) async throws
    func updateNote(id: UUID, note: String?) async throws
}

enum VideoItemRepositoryError: LocalizedError, Equatable {
    case duplicateVideo

    var errorDescription: String? {
        switch self {
        case .duplicateVideo:
            "This short is already in your Centralia library."
        }
    }
}
