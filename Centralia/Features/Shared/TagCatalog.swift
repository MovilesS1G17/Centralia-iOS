import Foundation

/// Tag rules shared by the library screens. They mirror what the backend
/// applies on save/update (`normalize_tags`): trim, drop blanks, drop
/// case-insensitive duplicates keeping the first spelling, cap at 60 characters.
enum TagCatalog {
    static let maximumLength = 60

    static func normalize(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in tags {
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { continue }
            result.append(String(tag.prefix(maximumLength)))
        }

        return result
    }

    /// Tags in use across `videos`, normalized and sorted alphabetically.
    /// The backend has no tags endpoint, so the list is derived on the client.
    static func available(from videos: [VideoItem]) -> [String] {
        sorted(normalize(videos.flatMap(\.tags)))
    }

    static func sorted(_ tags: [String]) -> [String] {
        tags.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func contains(_ tags: [String], _ tag: String) -> Bool {
        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return tags.contains { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
    }
}
