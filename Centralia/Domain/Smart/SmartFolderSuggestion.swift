import Foundation

/// A folder recommendation inferred from a video's imported metadata.
///
/// The Save flow can select a matching existing folder or create the suggested
/// folder with an appropriate icon, keeping the recommendation optional.
struct SmartFolderSuggestion: Equatable, Sendable {
    static let title = "Smart suggestion"

    let folderName: String
    let existingFolderID: UUID?
    let symbol: FolderSymbol

    var needsNewFolder: Bool { existingFolderID == nil }

    var actionTitle: String {
        needsNewFolder ? "Create \u{201C}\(folderName)\u{201D}" : "Use \u{201C}\(folderName)\u{201D}"
    }

    var message: String {
        needsNewFolder
            ? "This short looks like \(folderName). Create the folder and save it there?"
            : "This short looks like \(folderName)."
    }

    /// Returns nil when there is no meaningful recommendation or it is selected.
    static func make(
        suggestedFolderName: String?,
        folders: [LibraryFolder],
        selectedFolderID: UUID?
    ) -> SmartFolderSuggestion? {
        let name = (suggestedFolderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let existingFolder = folders.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard existingFolder?.id != selectedFolderID else { return nil }

        return SmartFolderSuggestion(
            folderName: existingFolder?.name ?? name,
            existingFolderID: existingFolder?.id,
            symbol: symbol(for: name)
        )
    }

    static func symbol(for folderName: String) -> FolderSymbol {
        switch folderName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "recipes", "food": .forkAndKnife
        case "fitness", "comedy": .heart
        case "wellbeing": .sun
        case "design": .paintpalette
        case "spaces": .house
        case "tech": .lightbulb
        case "travel": .camera
        case "music": .musicNote
        case "learning": .graduationCap
        default: .folder
        }
    }
}
