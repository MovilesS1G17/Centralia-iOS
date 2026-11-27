import CryptoKit
import Foundation

/// A derived cache keyed by the request inputs and the available folder IDs and names.
/// Only fingerprints, IDs and timestamps are written to disk.
actor FolderSuggestionCache {
    nonisolated struct Input: Encodable, Equatable, Sendable {
        let metadata: ImportedVideoMetadata
        let tags: [String]

        init(_ video: VideoItem) {
            metadata = ImportedVideoMetadata(
                sourceURL: video.sourceURL,
                platform: video.platform,
                creator: video.creator,
                durationSeconds: video.durationSeconds,
                sourceCaption: video.sourceCaption,
                transcript: video.transcript,
                extractedOnScreenText: video.extractedOnScreenText,
                generatedSummary: video.generatedSummary
            )
            tags = video.tags
        }
    }

    nonisolated struct FolderIdentity: Encodable, Equatable, Sendable {
        let id: UUID
        let name: String

        static func inventory(_ folders: [LibraryFolder]) -> [Self] {
            folders.map { Self(id: $0.id, name: $0.name) }.sorted { $0.id.uuidString < $1.id.uuidString }
        }
    }

    nonisolated struct Lookup: Sendable {
        let folderIDs: [UUID: UUID]
        fileprivate let accountID: UUID
        fileprivate let generation: Int
        fileprivate let fingerprints: [UUID: String]
    }

    nonisolated struct Update: Sendable {
        let videoID: UUID
        /// A successful lookup without a usable folder replaces any previous answer.
        let folderID: UUID?
    }

    private struct Entry: Codable, Sendable {
        let videoID: UUID
        let folderID: UUID
        let fingerprint: String
        let storedAt: Date
    }

    private let directory: URL
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder
    private var entriesByAccount: [UUID: [UUID: Entry]] = [:]
    private var generations: [UUID: Int] = [:]
    private let ttl: TimeInterval = 24 * 60 * 60
    private let capacity = 100

    init(
        directory: URL = URL.cachesDirectory.appending(path: "folder-suggestions-v1", directoryHint: .isDirectory),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directory = directory
        self.now = now
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        self.encoder = encoder
    }

    func lookup(for accountID: UUID, videos: [VideoItem], folders: [LibraryFolder]) -> Lookup {
        let entries = validEntries(for: accountID, at: now())
        let inventory = FolderIdentity.inventory(folders)
        let availableIDs = Set(inventory.map(\.id))
        var fingerprints: [UUID: String] = [:]
        var hits: [UUID: UUID] = [:]

        if let folderHash = fingerprint(inventory) {
            for video in videos {
                guard let inputHash = fingerprint(Input(video)) else { continue }
                let key = inputHash + folderHash
                fingerprints[video.id] = key
                if let entry = entries[video.id], entry.fingerprint == key, availableIDs.contains(entry.folderID) {
                    hits[video.id] = entry.folderID
                }
            }
        }

        return Lookup(
            folderIDs: hits,
            accountID: accountID,
            generation: generations[accountID, default: 0],
            fingerprints: fingerprints
        )
    }

    func save(_ updates: [Update], from lookup: Lookup) {
        let accountID = lookup.accountID
        guard !Task.isCancelled, !updates.isEmpty, lookup.generation == generations[accountID, default: 0] else { return }
        let date = now()
        var entries = validEntries(for: accountID, at: date)

        for update in updates {
            guard let key = lookup.fingerprints[update.videoID] else { continue }
            if let folderID = update.folderID {
                entries[update.videoID] = Entry(videoID: update.videoID, folderID: folderID, fingerprint: key, storedAt: date)
            } else if entries[update.videoID]?.fingerprint == key {
                entries[update.videoID] = nil
            }
        }

        let newest = entries.values.sorted {
            if $0.storedAt != $1.storedAt { return $0.storedAt > $1.storedAt }
            return $0.videoID.uuidString < $1.videoID.uuidString
        }.prefix(capacity)
        persist(Dictionary(uniqueKeysWithValues: newest.map { ($0.videoID, $0) }), for: accountID)
    }

    func clear(for accountID: UUID) {
        generations[accountID, default: 0] += 1
        entriesByAccount[accountID] = [:]
        try? FileManager.default.removeItem(at: fileURL(for: accountID))
    }

    private func validEntries(for accountID: UUID, at date: Date) -> [UUID: Entry] {
        let entries: [UUID: Entry]
        if let saved = entriesByAccount[accountID] {
            entries = saved
        } else {
            let data = try? Data(contentsOf: fileURL(for: accountID))
            let saved = data.flatMap { try? JSONDecoder().decode([UUID: Entry].self, from: $0) } ?? [:]
            entries = saved
            entriesByAccount[accountID] = saved
        }
        let valid = entries.filter {
            let age = date.timeIntervalSince($0.value.storedAt)
            return age >= 0 && age < ttl
        }
        if valid.count != entries.count { persist(valid, for: accountID) }
        return valid
    }

    private func persist(_ entries: [UUID: Entry], for accountID: UUID) {
        entriesByAccount[accountID] = entries
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: fileURL(for: accountID), options: [.atomic, .completeFileProtection])
        } catch {
            // The cache is recoverable, and suggestions remain usable for this run.
        }
    }

    private func fileURL(for accountID: UUID) -> URL {
        directory.appending(path: "\(accountID.uuidString).json", directoryHint: .notDirectory)
    }

    private func fingerprint<Value: Encodable>(_ value: Value) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }
}
