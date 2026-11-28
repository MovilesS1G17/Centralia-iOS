import SwiftUI
import UIKit

/// Caching + multithreading (Sprint 3) for covers.
///
/// - Memory: an `NSCache` of decoded images (the system empties it under
///   memory pressure).
/// - Disk: a 100 MB `URLCache` in Caches/covers with
///   `.returnCacheDataElseLoad` — cache falling back to network, so covers seen
///   once still show offline.
/// - Decoding a JPEG is slow, so it runs on a background GCD queue
///   (`DispatchQueue.global(qos: .userInitiated)`) and only the finished image
///   comes back to the main thread. This keeps scrolling smooth.
///
/// Mirrors the Coil memory + disk cache configured in `CentraliaApplication` on Android.
final class CoverImageLoader {
    static let shared = CoverImageLoader()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private nonisolated let responseCache: URLCache

    init() {
        memory.countLimit = 200
        let configuration = URLSessionConfiguration.default
        let responseCache = URLCache(
            memoryCapacity: 10 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            directory: URL.cachesDirectory.appending(path: "covers", directoryHint: .isDirectory)
        )
        self.responseCache = responseCache
        configuration.urlCache = responseCache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        guard let response = try? await session.data(from: url) else { return nil }
        let data = response.0
        guard let image = await Self.decodeInBackground(data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    nonisolated func cachedResponseData(for url: URL) -> Data? {
        responseCache.cachedResponse(for: URLRequest(url: url))?.data
    }

    /// Multithreading (Sprint 3, Gustavo): structured concurrency with a task group.
    ///
    /// When the Library finishes loading, the covers of the first cards are
    /// downloaded and decoded before the user scrolls to them. Each cover is a
    /// child task of one `withTaskGroup`, so they run in parallel, at most
    /// `maxConcurrent` at a time (a new one starts as soon as one finishes).
    /// The group returns how many covers are ready. Cancelling the caller
    /// (leaving the screen) cancels every child.
    @discardableResult
    func prefetch(_ urls: [URL], maxConcurrent: Int = 4) async -> Int {
        let pending = urls.filter { cachedImage(for: $0) == nil }
        guard !pending.isEmpty else { return urls.count }

        let loaded = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<min(maxConcurrent, pending.count) {
                guard let url = iterator.next() else { break }
                group.addTask { await self.image(for: url) != nil }
            }
            var ready = 0
            for await succeeded in group {
                if succeeded { ready += 1 }
                if Task.isCancelled { group.cancelAll(); break }
                if let url = iterator.next() {
                    group.addTask { await self.image(for: url) != nil }
                }
            }
            return ready
        }
        return loaded + (urls.count - pending.count)
    }

    func clear() {
        memory.removeAllObjects()
        responseCache.removeAllCachedResponses()
    }

    nonisolated private static func decodeInBackground(_ data: Data) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // preparingForDisplay() decodes now, here, instead of on the
                // main thread the first time the image is drawn.
                let image = UIImage(data: data)?.preparingForDisplay()
                continuation.resume(returning: image)
            }
        }
    }
}
