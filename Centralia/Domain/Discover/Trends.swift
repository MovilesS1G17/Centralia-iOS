import Foundation

/// `GET /v1/trends` returns community aggregates with a minimum user count.
nonisolated struct TrendItem: Codable, Equatable, Sendable, Identifiable {
    let name: String
    let saves: Int
    let users: Int
    var id: String { name }
}

nonisolated struct Trends: Codable, Equatable, Sendable {
    let generatedAt: Date
    let windowDays: Int
    let minUsers: Int
    let totalSaves: Int
    let categories: [TrendItem]
    let tags: [TrendItem]
    let platformCounts: [String: Int]
}

/// Where a Trends response came from.
nonisolated enum TrendsSource: String, Sendable {
    case memory, disk, network
}

nonisolated struct TrendsResult: Sendable {
    let trends: Trends
    let source: TrendsSource
    let fetchedAt: Date
    /// Older than the cache lifetime: shown because the network failed.
    let isStale: Bool
}

nonisolated struct CachedTrends: Codable, Sendable {
    let trends: Trends
    let fetchedAt: Date
}

nonisolated struct TrendsUnavailableError: LocalizedError, Sendable {
    var errorDescription: String? { CachedTrendsRepository.offlineMessage }
}

/// Disk level (a JSON file per window in Caches/trends).
nonisolated protocol TrendsDiskStoring: Sendable {
    func read(windowDays: Int) async -> CachedTrends?
    func write(_ value: CachedTrends, windowDays: Int) async
    func clear() async
}

nonisolated protocol TrendsLoading: Sendable {
    func load(windowDays: Int, forceRefresh: Bool) async throws -> TrendsResult
    func clear() async
}

/// Reads fresh results from memory or disk before fetching from the API.
/// A failed refresh can reuse the last successful response for that window.
actor CachedTrendsRepository: TrendsLoading {
    static let ttl: TimeInterval = 10 * 60
    nonisolated static let offlineMessage =
        "Trends needs a connection the first time. Connect to the internet and we'll keep a copy on your phone for next time."

    private struct Load {
        let task: Task<TrendsResult, Error>
        let forceRefresh: Bool
    }

    private let fetch: @Sendable (Int) async throws -> Trends
    private let disk: any TrendsDiskStoring
    private let now: @Sendable () -> Date
    private var memory = LRUCache<Int, CachedTrends>(capacity: 4)
    private var inFlight: [Int: Load] = [:]
    private var pendingClear: Task<Void, Never>?

    init(
        fetch: @escaping @Sendable (Int) async throws -> Trends,
        disk: any TrendsDiskStoring,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetch = fetch
        self.disk = disk
        self.now = now
    }

    func load(windowDays: Int, forceRefresh: Bool = false) async throws -> TrendsResult {
        await pendingClear?.value
        try Task.checkCancellation()
        if !forceRefresh, let cached = memory.value(for: windowDays), isFresh(cached) {
            return result(cached, source: .memory)
        }

        if let pending = inFlight[windowDays] {
            let loaded = try await pending.task.value
            // A refresh can share a network request already in progress, but
            // should still reach the network after a disk hit.
            if forceRefresh, !pending.forceRefresh, loaded.source == .disk, !loaded.isStale {
                return try await load(windowDays: windowDays, forceRefresh: true)
            }
            return loaded
        }

        let task = Task {
            defer {
                if !Task.isCancelled { inFlight[windowDays] = nil }
            }
            return try await readOrFetch(windowDays: windowDays, forceRefresh: forceRefresh)
        }
        inFlight[windowDays] = Load(task: task, forceRefresh: forceRefresh)
        return try await task.value
    }

    private func readOrFetch(windowDays: Int, forceRefresh: Bool) async throws -> TrendsResult {
        let onDisk = await disk.read(windowDays: windowDays)
        try Task.checkCancellation()
        if !forceRefresh, let onDisk, isFresh(onDisk) {
            memory.insert(onDisk, for: windowDays)
            return result(onDisk, source: .disk)
        }

        do {
            let fresh = CachedTrends(trends: try await fetch(windowDays), fetchedAt: now())
            try Task.checkCancellation()
            await disk.write(fresh, windowDays: windowDays)
            try Task.checkCancellation()
            memory.insert(fresh, for: windowDays)
            return result(fresh, source: .network)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            if let cached = memory.value(for: windowDays),
               onDisk.map({ cached.fetchedAt >= $0.fetchedAt }) ?? true {
                return result(cached, source: .memory)
            }
            if let onDisk {
                memory.insert(onDisk, for: windowDays)
                return result(onDisk, source: .disk)
            }
            throw TrendsUnavailableError()
        }
    }

    func clear() async {
        memory.removeAll()
        let pendingRequests = inFlight.values.map(\.task)
        pendingRequests.forEach { $0.cancel() }
        inFlight.removeAll()

        let previous = pendingClear
        let clearing = Task {
            await previous?.value
            for request in pendingRequests { _ = await request.result }
            await disk.clear()
        }
        pendingClear = clearing
        await clearing.value
    }

    private func isFresh(_ cached: CachedTrends) -> Bool {
        now().timeIntervalSince(cached.fetchedAt) < Self.ttl
    }

    private func result(_ cached: CachedTrends, source: TrendsSource) -> TrendsResult {
        TrendsResult(trends: cached.trends, source: source, fetchedAt: cached.fetchedAt, isStale: !isFresh(cached))
    }

    /// "Updated just now" / "Updated 5 min ago" / "Updated 3 h ago" / "Updated 2 days ago".
    nonisolated static func updatedLabel(_ fetchedAt: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
        switch minutes {
        case ..<1: return "Updated just now"
        case ..<60: return "Updated \(minutes) min ago"
        case ..<(60 * 24): return "Updated \(minutes / 60) h ago"
        default: return "Updated \(minutes / (60 * 24)) days ago"
        }
    }
}

/// One JSON file per window in `Caches/trends`. iOS may purge Caches when
/// space is low, which is fine for a cache. Written atomically.
actor FileTrendsDiskStore: TrendsDiskStoring {
    private let directory: URL

    init(directory: URL = URL.cachesDirectory.appending(path: "trends", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    private func file(_ windowDays: Int) -> URL { directory.appending(path: "trends-\(windowDays).json") }

    func read(windowDays: Int) async -> CachedTrends? {
        guard let data = try? Data(contentsOf: file(windowDays)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedTrends.self, from: data)
    }

    func write(_ value: CachedTrends, windowDays: Int) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: file(windowDays), options: .atomic)
    }

    func clear() async {
        try? FileManager.default.removeItem(at: directory)
    }
}

actor InMemoryTrendsDiskStore: TrendsDiskStoring {
    private var files: [Int: CachedTrends] = [:]
    func read(windowDays: Int) async -> CachedTrends? { files[windowDays] }
    func write(_ value: CachedTrends, windowDays: Int) async { files[windowDays] = value }
    func clear() async { files = [:] }
}

/// `GET /v1/trends?days=…`.
nonisolated struct APITrendsClient: Sendable {
    let client: APIClient

    func trends(windowDays: Int) async throws -> Trends {
        try await client.request(
            Trends.self,
            path: "/v1/trends",
            query: [URLQueryItem(name: "days", value: String(windowDays))],
            timeout: 10
        )
    }

    /// Trends for the mock build (no server).
    static func sample(windowDays: Int) -> Trends {
        Trends(
            generatedAt: Date(),
            windowDays: windowDays,
            minUsers: 3,
            totalSaves: 128,
            categories: [TrendItem(name: "Recipes", saves: 34, users: 12), TrendItem(name: "Fitness", saves: 21, users: 9), TrendItem(name: "Travel", saves: 17, users: 8)],
            tags: [TrendItem(name: "Pasta", saves: 15, users: 7), TrendItem(name: "Workout", saves: 11, users: 6), TrendItem(name: "Beach", saves: 8, users: 4)],
            platformCounts: ["tiktok": 61, "instagramReel": 33, "youtubeShort": 34]
        )
    }
}
