import Foundation

struct LibraryFolder: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: UUID
    var name: String
    let symbolName: String
}
