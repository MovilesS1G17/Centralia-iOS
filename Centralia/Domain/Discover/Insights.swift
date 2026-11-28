import Foundation

nonisolated struct WeekBar: Codable, Equatable, Sendable, Identifiable {
    /// Monday of the week, ISO date ("2026-11-23").
    let weekStart: String
    let saves: Int
    var id: String { weekStart }
}

/// Insights (Sprint 4, Gustavo): the user's own saving habits, computed on the
/// phone from the library (so it works offline). The last snapshot is kept in
/// a JSON file: the screen shows it at once, and the difference with the new
/// one is "Since your last visit". Same numbers as Android.
nonisolated struct InsightsSnapshot: Codable, Equatable, Sendable {
    let computedAt: Date
    let totalSaves: Int
    let weeks: [WeekBar]
    let platformCounts: [String: Int]
    /// % of shorts in a folder.
    let inFolderPct: Int
    let topTags: [String]
    /// Weeks in a row, up to this one, with at least one save.
    let streakWeeks: Int

    var thisWeek: Int { weeks.last?.saves ?? 0 }
    var lastWeek: Int { weeks.count >= 2 ? weeks[weeks.count - 2].saves : 0 }
    var weekChange: Int { thisWeek - lastWeek }
    var averagePerWeek: Double { weeks.isEmpty ? 0 : Double(weeks.map(\.saves).reduce(0, +)) / Double(weeks.count) }
}

nonisolated enum Insights {
    static let weeks = 8

    /// A Gregorian calendar whose weeks start on Monday (like ISO weeks), in `timeZone`.
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        calendar.timeZone = timeZone
        return calendar
    }

    static func monday(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func compute(_ videos: [VideoFacts], now: Date, calendar: Calendar = calendar(), weeks: Int = weeks) -> InsightsSnapshot {
        let thisMonday = monday(of: now, calendar: calendar)
        let starts = (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisMonday) }
        var counts = Array(repeating: 0, count: starts.count)
        var mondays = Set<Date>()
        var tagCounts: [String: Int] = [:]
        for video in videos {
            let start = monday(of: video.savedAt, calendar: calendar)
            mondays.insert(start)
            if let index = starts.firstIndex(of: start) { counts[index] += 1 }
            for tag in Set(video.tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }) where !tag.isEmpty {
                tagCounts[tag, default: 0] += 1
            }
        }
        var streak = 0
        var monday = thisMonday
        while mondays.contains(monday) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: monday) else { break }
            monday = previous
        }
        let inFolder = videos.filter { $0.folderID != nil }.count
        return InsightsSnapshot(
            computedAt: now,
            totalSaves: videos.count,
            weeks: zip(starts, counts).map { WeekBar(weekStart: isoDay($0, calendar: calendar), saves: $1) },
            platformCounts: Dictionary(grouping: videos, by: \.platformRaw).mapValues(\.count),
            inFolderPct: videos.isEmpty ? 0 : Int((100 * Double(inFolder) / Double(videos.count)).rounded()),
            topTags: tagCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5).map(\.key),
            streakWeeks: streak
        )
    }

    /// New saves since the stored snapshot, nil on the first visit.
    static func sinceLastVisit(_ previous: InsightsSnapshot?, _ current: InsightsSnapshot) -> Int? {
        previous.map { current.totalSaves - $0.totalSaves }
    }

    /// "Nov 23" for a bar label.
    static func shortLabel(_ weekStart: String) -> String {
        let parts = weekStart.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return weekStart }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[parts[1] - 1]) \(parts[2])"
    }
}

nonisolated protocol InsightsSnapshotStoring: Sendable {
    func load() async -> InsightsSnapshot?
    func save(_ snapshot: InsightsSnapshot) async
    func clear() async
}

/// Local storage (files): the last snapshot as JSON in Application Support,
/// written atomically and protected while the phone is locked.
nonisolated struct FileInsightsSnapshotStore: InsightsSnapshotStoring {
    let file: URL

    init(file: URL = URL.applicationSupportDirectory.appending(path: "insights/last_snapshot.json")) {
        self.file = file
    }

    init(accountID: UUID) {
        self.init(file: URL.applicationSupportDirectory.appending(path: "insights/\(accountID.uuidString).json"))
    }

    func load() async -> InsightsSnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InsightsSnapshot.self, from: data)
    }

    func save(_ snapshot: InsightsSnapshot) async {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtection])
    }

    func clear() async {
        try? FileManager.default.removeItem(at: file)
    }
}

actor InMemoryInsightsSnapshotStore: InsightsSnapshotStoring {
    private var snapshot: InsightsSnapshot?
    func load() async -> InsightsSnapshot? { snapshot }
    func save(_ snapshot: InsightsSnapshot) async { self.snapshot = snapshot }
    func clear() async { snapshot = nil }
}
