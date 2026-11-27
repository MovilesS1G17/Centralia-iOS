import Foundation

/// Tag rules shared by the library screens. They mirror what the backend
/// applies on save/update (`normalize_tags`): trim, drop blanks, drop
/// case-insensitive duplicates keeping the first spelling, at most 30
/// characters (`MAX_TAG_LENGTH`; TA feedback: long tags broke the layout).
enum TagCatalog {
    static let maximumLength = TagRules.maxLength

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

/// The rules for a tag being typed, shared by both tag editors. Same as
/// `TagRules.kt` on Android and `MAX_TAG_LENGTH` in the API.
nonisolated enum TagRules {
    static let maxLength = 30

    /// Trims and collapses inner spaces, the same way the server does.
    static func clean(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// What the text field keeps while typing: never more than `maxLength` characters.
    static func limitInput(_ raw: String) -> String {
        raw.count <= maxLength ? raw : String(raw.prefix(maxLength))
    }

    /// The "12/30" counter under a tag field.
    static func counter(_ raw: String) -> String {
        "\(clean(raw).count)/\(maxLength)"
    }

    static func isValid(_ raw: String) -> Bool {
        let tag = clean(raw)
        return !tag.isEmpty && tag.count <= maxLength
    }

    /// Adds `raw` to `tags` if valid and not already there (ignoring case).
    /// "Add", "Done" and "Save" all use it, so a typed tag is never lost
    /// (TA feedback: "Done should save what you just did").
    static func addingPending(_ raw: String, to tags: [String]) -> [String] {
        let tag = clean(raw)
        guard isValid(tag),
              !tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else {
            return tags
        }
        return tags + [tag]
    }
}
