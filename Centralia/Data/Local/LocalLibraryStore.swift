import Foundation

/// Local storage (Sprint 3): the last copy of the library the phone saw, as a
/// JSON file in Application Support (`offline/library.json`). It lets the
/// Library, Search and Folders screens open with no connection.
///
/// It is an `actor`, so reads and writes happen one at a time and off the
/// main thread; the file is written atomically (temp file + rename), so a crash
/// mid-write never leaves a broken copy. Mirrors `LocalLibraryStore` on Android.
actor LocalLibraryStore {
    nonisolated struct Snapshot: Codable, Equatable, Sendable {
        var videos: [VideoItem] = []
        var folders: [LibraryFolder] = []
        var savedAt: Date?
    }

    private let fileURL: URL
    private var cached: Snapshot?
    private let encoder = OfflineJSON.encoder()
    private let decoder = OfflineJSON.decoder()

    init(directory: URL = LocalLibraryStore.defaultDirectory) {
        fileURL = directory.appending(path: "library.json")
    }

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "offline", directoryHint: .isDirectory)
    }

    func read() -> Snapshot {
        if let cached { return cached }
        let snapshot = (try? Data(contentsOf: fileURL))
            .flatMap { try? decoder.decode(Snapshot.self, from: $0) } ?? Snapshot()
        cached = snapshot
        return snapshot
    }

    @discardableResult
    func update(_ transform: @Sendable (Snapshot) -> Snapshot) -> Snapshot {
        let updated = transform(read())
        cached = updated
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try encoder.encode(updated).write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // The in-memory copy still works; the next write tries again.
        }
        return updated
    }

    func clear() {
        cached = Snapshot()
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// The JSON format of the offline files (dates as ISO-8601).
nonisolated enum OfflineJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
