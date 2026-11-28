import Foundation

/// One short Rediscover brings back, with why it was picked.
nonisolated struct RediscoverPick: Equatable, Sendable, Identifiable {
    let videoID: UUID
    let daysSinceSaved: Int
    /// Days since it was last opened on this phone, nil if never.
    let daysSinceViewed: Int?
    let score: Double

    var id: UUID { videoID }

    var reason: String {
        if let daysSinceViewed {
            return "Last opened \(daysSinceViewed) days ago"
        }
        return "Saved \(daysSinceSaved) days ago and never opened since"
    }
}

/// Rediscover (Sprint 4, Enrique; mirrored on iOS). Shorts saved at least
/// `minAgeDays` ago that haven't been opened in the last `quietDays`. Older and
/// longer-forgotten shorts score higher; a jitter that changes once a day keeps
/// the list fresh each day and stable within it. Same rules as Android.
///
/// Multithreading: `pickInParallel` scores the candidates in chunks, one child
/// task per chunk in a `withTaskGroup`, off the main actor.
nonisolated enum Rediscover {
    static let minAgeDays = 7
    static let quietDays = 14
    static let limit = 6
    static let dismissDays = 30

    static func days(from start: Date, to end: Date) -> Int {
        Int(end.timeIntervalSince(start) / 86_400)
    }

    static func candidates(
        _ videos: [VideoFacts],
        lastViewed: [UUID: Date],
        dismissed: Set<UUID>,
        now: Date
    ) -> [VideoFacts] {
        videos.filter { video in
            guard days(from: video.savedAt, to: now) >= minAgeDays, !dismissed.contains(video.id) else { return false }
            guard let viewed = lastViewed[video.id] else { return true }
            return days(from: viewed, to: now) >= quietDays
        }
    }

    static func score(_ video: VideoFacts, lastViewed: Date?, now: Date, daySeed: Int) -> RediscoverPick {
        let age = days(from: video.savedAt, to: now)
        let quiet = lastViewed.map { days(from: $0, to: now) }
        var score = Double(min(age, 120))
        score += quiet.map { Double(min($0, 90)) * 0.5 } ?? 30
        if video.folderID != nil || !video.tags.isEmpty { score += 5 }
        score += jitter(video.id, daySeed: daySeed) * 20
        return RediscoverPick(videoID: video.id, daysSinceSaved: age, daysSinceViewed: quiet, score: score)
    }

    static func daySeed(_ now: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.startOfDay(for: now)
        return Int(day.timeIntervalSince1970 / 86_400)
    }

    static func pick(
        _ videos: [VideoFacts],
        lastViewed: [UUID: Date],
        dismissed: Set<UUID>,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = limit
    ) -> [RediscoverPick] {
        guard limit > 0 else { return [] }
        let seed = daySeed(now, calendar: calendar)
        return Array(
            candidates(videos, lastViewed: lastViewed, dismissed: dismissed, now: now)
                .map { score($0, lastViewed: lastViewed[$0.id], now: now, daySeed: seed) }
                .sorted(by: ordered)
                .prefix(limit)
        )
    }

    static func pickInParallel(
        _ videos: [VideoFacts],
        lastViewed: [UUID: Date],
        dismissed: Set<UUID>,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = limit,
        chunks: Int = 4
    ) async -> [RediscoverPick] {
        let seed = daySeed(now, calendar: calendar)
        let candidates = candidates(videos, lastViewed: lastViewed, dismissed: dismissed, now: now)
        guard !candidates.isEmpty, limit > 0 else { return [] }
        let chunks = min(max(1, chunks), candidates.count)
        let size = (candidates.count + chunks - 1) / chunks
        let slices = stride(from: 0, to: candidates.count, by: size).map {
            Array(candidates[$0..<min($0 + size, candidates.count)])
        }
        let partial = await withTaskGroup(of: [RediscoverPick].self) { group in
            for slice in slices {
                group.addTask {
                    Array(slice.map { score($0, lastViewed: lastViewed[$0.id], now: now, daySeed: seed) }
                        .sorted(by: ordered)
                        .prefix(limit))
                }
            }
            var all: [RediscoverPick] = []
            for await picks in group { all.append(contentsOf: picks) }
            return all
        }
        return Array(partial.sorted(by: ordered).prefix(limit))
    }

    private static func ordered(_ a: RediscoverPick, _ b: RediscoverPick) -> Bool {
        a.score != b.score ? a.score > b.score : a.videoID.uuidString < b.videoID.uuidString
    }

    /// 0 ≤ jitter < 1, the same for one short on one day.
    private static func jitter(_ id: UUID, daySeed: Int) -> Double {
        // Swift's Hasher is seeded per launch, so this mixes by hand (FNV + a
        // finalizer) to get a value that stays the same across launches.
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        var x: UInt64 = UInt64(bitPattern: Int64(daySeed)) &* 0x9E37_79B9_7F4A_7C15
        for byte in bytes { x = (x ^ UInt64(byte)) &* 0x100_0000_01B3 }
        x ^= x >> 33
        x = x &* 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33
        return Double(x >> 11) / Double(UInt64(1) << 53)
    }
}

/// "Not now" on a Rediscover card hides that short for `Rediscover.dismissDays` days.
nonisolated protocol RediscoverDismissing: Sendable {
    func active(now: Date) -> Set<UUID>
    func dismiss(_ videoID: UUID, at date: Date)
}

/// Key/value storage: `UserDefaults` (short id → when it was dismissed).
nonisolated final class UserDefaultsRediscoverDismissals: RediscoverDismissing, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private static let lock = NSLock()

    init(accountID: UUID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "centralia.rediscover.dismissed.\(accountID.uuidString)"
    }

    func active(now: Date) -> Set<UUID> {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        let fresh = stored.filter { Rediscover.days(from: Date(timeIntervalSince1970: $0.value), to: now) < Rediscover.dismissDays }
        if fresh.count != stored.count { defaults.set(fresh, forKey: key) }
        return Set(fresh.keys.compactMap(UUID.init(uuidString:)))
    }

    func dismiss(_ videoID: UUID, at date: Date) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        stored[videoID.uuidString] = date.timeIntervalSince1970
        defaults.set(stored, forKey: key)
    }

}
