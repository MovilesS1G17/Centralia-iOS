import Foundation

/// Everything saved from one creator (ids only, so it can be built off the main actor).
nonisolated struct CreatorSummary: Equatable, Sendable, Identifiable {
    let handle: String
    let platformsRaw: [String]
    /// Newest first.
    let videoIDs: [UUID]
    let lastSavedAt: Date

    var id: String { Creators.key(handle) }
    var count: Int { videoIDs.count }
    var initial: String {
        handle.drop(while: { $0 == "@" }).first.map { String($0).uppercased() } ?? "?"
    }
}

/// Creators (Sprint 4, Alejandro). Saved shorts grouped by creator, most saved
/// first; the same handle on TikTok and Instagram is one creator.
///
/// Multithreading: `groupInParallel` groups each platform's shorts in its own
/// child task (`withTaskGroup`) and merges the partial groups.
/// Caching: `CreatorsCache` (the hand-written LRU) keeps the result per
/// library fingerprint, so returning to the screen doesn't regroup.
nonisolated enum Creators {
    static func key(_ handle: String) -> String {
        handle.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "@" })
            .lowercased()
    }

    /// Cheap identity of a library: one pass, no allocation.
    static func fingerprint(_ videos: [VideoFacts]) -> Int {
        var hasher = Hasher()
        hasher.combine(videos.count)
        for video in videos {
            hasher.combine(video.id)
            hasher.combine(video.creator)
            hasher.combine(video.platformRaw)
            hasher.combine(video.savedAt)
        }
        return hasher.finalize()
    }

    static func group(_ videos: [VideoFacts]) -> [CreatorSummary] {
        merge([partial(videos)])
    }

    static func groupInParallel(_ videos: [VideoFacts]) async -> [CreatorSummary] {
        let slices = Dictionary(grouping: videos, by: \.platformRaw).values
        let partials = await withTaskGroup(of: [String: [VideoFacts]].self) { group in
            for slice in slices {
                group.addTask { partial(slice) }
            }
            var all: [[String: [VideoFacts]]] = []
            for await partial in group { all.append(partial) }
            return all
        }
        return merge(partials)
    }

    private static func partial(_ videos: [VideoFacts]) -> [String: [VideoFacts]] {
        Dictionary(grouping: videos.filter { !key($0.creator).isEmpty }, by: { key($0.creator) })
    }

    private static let platformOrder = ["tiktok", "instagramReel", "youtubeShort"]

    private static func merge(_ partials: [[String: [VideoFacts]]]) -> [CreatorSummary] {
        var all: [String: [VideoFacts]] = [:]
        for partial in partials {
            for (key, list) in partial { all[key, default: []].append(contentsOf: list) }
        }
        return all.values.map { list in
            let newestFirst = list.sorted { a, b in
                if a.savedAt != b.savedAt { return a.savedAt > b.savedAt }
                return a.id.uuidString < b.id.uuidString
            }
            let platforms = Set(newestFirst.map(\.platformRaw))
            return CreatorSummary(
                handle: newestFirst[0].creator.trimmingCharacters(in: .whitespacesAndNewlines),
                platformsRaw: platformOrder.filter(platforms.contains),
                videoIDs: newestFirst.map(\.id),
                lastSavedAt: newestFirst[0].savedAt
            )
        }
        .sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            if a.lastSavedAt != b.lastSavedAt { return a.lastSavedAt > b.lastSavedAt }
            return key(a.handle) < key(b.handle)
        }
    }
}

/// LRU of grouped creators by library fingerprint. Thread-safe with a lock.
nonisolated final class CreatorsCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache = LRUCache<Int, [CreatorSummary]>(capacity: 4)

    func value(for fingerprint: Int) -> [CreatorSummary]? {
        lock.lock()
        defer { lock.unlock() }
        return cache.value(for: fingerprint)
    }

    func insert(_ value: [CreatorSummary], for fingerprint: Int) {
        lock.lock()
        defer { lock.unlock() }
        cache.insert(value, for: fingerprint)
    }

}
