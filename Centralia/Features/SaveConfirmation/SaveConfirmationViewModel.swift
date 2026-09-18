import Foundation
import Observation

@Observable
final class SaveConfirmationViewModel {
    private let videoRepository: any VideoItemRepository

    private(set) var video: VideoItem
    private(set) var isSavingNote = false
    private(set) var failureMessage: String?

    var shouldShowAddNote: Bool {
        guard let note = video.note else { return true }
        return note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        video: VideoItem,
        videoRepository: any VideoItemRepository
    ) {
        self.video = video
        self.videoRepository = videoRepository
    }

    @discardableResult
    func saveNote(_ note: String) async -> Bool {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty, !isSavingNote else { return false }

        isSavingNote = true
        failureMessage = nil
        defer { isSavingNote = false }

        do {
            try await videoRepository.updateNote(id: video.id, note: trimmedNote)
            video.note = trimmedNote
            return true
        } catch {
            failureMessage = error.localizedDescription
            return false
        }
    }

    func dismissFailure() {
        failureMessage = nil
    }
}
