import Foundation

enum FolderSymbol: String, CaseIterable, Codable, Identifiable, Sendable {
    case folder
    case house
    case paintpalette
    case forkAndKnife = "fork.knife"
    case books = "books.vertical"
    case lightbulb
    case briefcase
    case heart
    case graduationCap = "graduationcap"
    case camera
    case musicNote = "music.note"
    case sun = "sun.max"

    var id: String { rawValue }

    var accessibilityName: String {
        switch self {
        case .folder: "Folder"
        case .house: "Home"
        case .paintpalette: "Design"
        case .forkAndKnife: "Food"
        case .books: "Books"
        case .lightbulb: "Ideas"
        case .briefcase: "Work"
        case .heart: "Favorites"
        case .graduationCap: "Learning"
        case .camera: "Photography"
        case .musicNote: "Music"
        case .sun: "Wellbeing"
        }
    }
}
