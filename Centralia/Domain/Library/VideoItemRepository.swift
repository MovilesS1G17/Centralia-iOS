import Foundation

protocol VideoItemRepository {
    func videos() async throws -> [VideoItem]
    func deleteVideo(id: UUID) async throws
    func restoreVideo(_ video: VideoItem) async throws
    func moveVideo(id: UUID, to folderID: UUID?) async throws
}
