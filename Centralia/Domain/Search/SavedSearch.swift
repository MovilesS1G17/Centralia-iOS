import Foundation

nonisolated struct SavedSearch: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let criteria: VideoSearchCriteria
}
