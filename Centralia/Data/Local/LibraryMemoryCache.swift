import Foundation

/// Caching (Sprint 3): the in-memory layer in front of the disk copy and the
/// network.
///
/// - The library and folder lists stay in memory while the app runs, so moving
///   between Library, Search and Folders offline doesn't re-read the file.
/// - Playback answers live in an `NSCache` (32 shorts, evicted by the system
///   under memory pressure) for 10 minutes. Re-opening a short you just watched
///   skips the `/playback` request; the signed MP4 link is valid for 6 hours.
///   The key includes the network, because on mobile data the backend answers
///   differently (data saver).
///
/// Covers have their own memory + disk cache (`CoverImageLoader`). Mirrors
/// `LibraryMemoryCache` on Android.
final class LibraryMemoryCache {
    var videos: [VideoItem]?
    var folders: [LibraryFolder]?

    private final class Entry {
        let playback: VideoPlayback
        let storedAt: Date
        init(playback: VideoPlayback, storedAt: Date) {
            self.playback = playback
            self.storedAt = storedAt
        }
    }

    private let playbackCache = NSCache<NSString, Entry>()
    private let playbackTTL: TimeInterval
    private let now: () -> Date

    init(playbackTTL: TimeInterval = 10 * 60, now: @escaping () -> Date = Date.init) {
        self.playbackTTL = playbackTTL
        self.now = now
        playbackCache.countLimit = 32
    }

    func playback(for id: UUID, network: NetworkType) -> VideoPlayback? {
        let key = Self.key(id, network)
        guard let entry = playbackCache.object(forKey: key) else { return nil }
        guard now().timeIntervalSince(entry.storedAt) <= playbackTTL else {
            playbackCache.removeObject(forKey: key)
            return nil
        }
        return entry.playback
    }

    func store(_ playback: VideoPlayback, for id: UUID, network: NetworkType) {
        playbackCache.setObject(Entry(playback: playback, storedAt: now()), forKey: Self.key(id, network))
    }

    func clear() {
        videos = nil
        folders = nil
        playbackCache.removeAllObjects()
    }

    private static func key(_ id: UUID, _ network: NetworkType) -> NSString {
        "\(id.uuidString.lowercased())|\(network.rawValue)" as NSString
    }
}
