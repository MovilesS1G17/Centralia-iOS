import Foundation

/// Named searches are local user data. A single actor serializes each read-modify-write.
actor SavedSearchStore {
    enum StoreError: LocalizedError {
        case emptyName, emptySearch, missingSearch

        var errorDescription: String? {
            switch self {
            case .emptyName: "Enter a name for this search."
            case .emptySearch: "Enter a search or select a filter first."
            case .missingSearch: "This saved search is no longer available."
            }
        }
    }

    private let directory: URL

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "saved-searches", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    func searches(for userID: UUID) throws -> [SavedSearch] {
        do {
            let data = try Data(contentsOf: fileURL(for: userID))
            return try JSONDecoder().decode([SavedSearch].self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
    }

    func create(named name: String, criteria: VideoSearchCriteria, for userID: UUID) throws -> [SavedSearch] {
        var criteria = criteria
        criteria.text = criteria.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard criteria.isSaveable else { throw StoreError.emptySearch }
        let search = SavedSearch(id: UUID(), name: try validatedName(name), criteria: criteria)
        let updated = [search] + (try searches(for: userID))
        try write(updated, for: userID)
        return updated
    }

    func rename(_ id: UUID, to name: String, for userID: UUID) throws -> [SavedSearch] {
        var updated = try searches(for: userID)
        guard let index = updated.firstIndex(where: { $0.id == id }) else { throw StoreError.missingSearch }
        updated[index].name = try validatedName(name)
        try write(updated, for: userID)
        return updated
    }

    func remove(_ id: UUID, for userID: UUID) throws -> [SavedSearch] {
        let current = try searches(for: userID)
        let updated = current.filter { $0.id != id }
        if updated.count != current.count { try write(updated, for: userID) }
        return updated
    }

    private func write(_ searches: [SavedSearch], for userID: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(searches).write(to: fileURL(for: userID), options: [.atomic, .completeFileProtection])
    }

    private func fileURL(for userID: UUID) -> URL {
        directory.appending(path: "\(userID.uuidString).json", directoryHint: .notDirectory)
    }

    private func validatedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyName }
        return trimmed
    }
}
