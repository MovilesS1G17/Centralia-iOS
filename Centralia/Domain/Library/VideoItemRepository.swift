import Foundation

protocol VideoItemRepository {
    func videos() async throws -> [VideoItem]
    func saveVideo(_ video: VideoItem) async throws
    /// Soft delete; the answer carries the shake-to-undo pop-up.
    @discardableResult
    func deleteVideo(id: UUID) async throws -> VideoDeletion
    func restoreVideo(_ video: VideoItem) async throws
    /// Same as `restoreVideo(_:)`, telling the backend whether the user shook
    /// the phone or tapped Undo (Sprint 3 BQ8).
    func restoreVideo(_ video: VideoItem, method: UndoMethod) async throws
    func moveVideo(id: UUID, to folderID: UUID?) async throws
    func updateNote(id: UUID, note: String?) async throws
    func updateTags(id: UUID, tags: [String]) async throws
    func recordSourceOpened(id: UUID) async
}

/// Shake to undo: the answer to `DELETE /v1/videos/{id}`. The backend decides
/// what the undo pop-up says and until when the short can be restored; the app
/// only shows it. Mirrors `VideoDeletion` in the Android app.
struct VideoDeletion: Equatable {
    /// Same text the backend sends; used offline (mock repository).
    static let defaultUndoMessage = "If you want to undo the delete, just shake the phone."
    /// Same window as the backend's UNDO_WINDOW_SECONDS default.
    static let undoWindowSeconds: TimeInterval = 300

    let videoID: UUID
    var undoMessage: String = VideoDeletion.defaultUndoMessage
    var undoExpiresAt: Date?

    static func local(videoID: UUID, now: Date = .now) -> VideoDeletion {
        VideoDeletion(videoID: videoID, undoExpiresAt: now.addingTimeInterval(undoWindowSeconds))
    }
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

extension VideoItemRepository {
    func recordSourceOpened(id: UUID) async {}

    /// Repositories that don't report the undo method (mocks, test fakes).
    func restoreVideo(_ video: VideoItem, method: UndoMethod) async throws {
        try await restoreVideo(video)
    }
}
