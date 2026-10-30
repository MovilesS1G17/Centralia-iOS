import Foundation

/// How the user undid a delete: shaking the phone or tapping Undo. Sent to the
/// backend as `X-Undo-Method` (Sprint 3 BQ8). Mirrors `UndoMethod` on Android.
enum UndoMethod: String, Codable, Sendable {
    case shake
    case button
}
