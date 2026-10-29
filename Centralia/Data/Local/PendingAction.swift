import Foundation

/// Eventual connectivity (Sprint 3): a change the user made while offline,
/// waiting in the outbox to be sent when the phone is back online. `queuedAt`
/// travels with it as `X-Queued-At`, so the backend knows how long it waited.
/// Mirrors `PendingAction` in the Android app (same rules).
///
/// `nonisolated`: plain data, used from the outbox actor and the main thread.
nonisolated struct PendingAction: Codable, Equatable, Sendable {
    nonisolated enum Kind: Codable, Equatable, Sendable {
        case delete
        case restore(method: UndoMethod)
        case move(folderID: UUID?)
        case note(String?)
        case tags([String])
    }

    let videoID: UUID
    let queuedAt: Date
    let kind: Kind

    /// The same change applied to a local copy of the library.
    func apply(to videos: [VideoItem]) -> [VideoItem] {
        switch kind {
        case .delete:
            return videos.filter { $0.id != videoID }
        case .restore:
            return videos
        case let .move(folderID):
            return videos.map { video in
                guard video.id == videoID else { return video }
                var copy = video
                copy.folderID = folderID
                return copy
            }
        case let .note(note):
            return videos.map { video in
                guard video.id == videoID else { return video }
                var copy = video
                copy.note = note
                return copy
            }
        case let .tags(tags):
            return videos.map { video in
                guard video.id == videoID else { return video }
                var copy = video
                copy.tags = tags
                return copy
            }
        }
    }

    /// True when `other` makes this one pointless (a newer edit of the same kind).
    func isReplaced(by other: PendingAction) -> Bool {
        guard videoID == other.videoID else { return false }
        switch (kind, other.kind) {
        case (.move, .move), (.note, .note), (.tags, .tags):
            return true
        default:
            return false
        }
    }

    var isDelete: Bool {
        if case .delete = kind { return true }
        return false
    }

    /// Pure outbox rule, shared by the queue and its tests: an undo of a delete
    /// that never reached the server cancels both; a newer edit of the same
    /// kind replaces the older one.
    static func enqueue(_ action: PendingAction, into current: [PendingAction]) -> [PendingAction] {
        if case .restore = action.kind,
           current.contains(where: { $0.isDelete && $0.videoID == action.videoID }) {
            return current.filter { !($0.isDelete && $0.videoID == action.videoID) }
        }
        return current.filter { !$0.isReplaced(by: action) } + [action]
    }

    /// ISO-8601 with milliseconds, the format the backend reads in `X-Queued-At`.
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
