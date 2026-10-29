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

    init() {
        memory.countLimit = 200
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 10 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            directory: URL.cachesDirectory.appending(path: "covers", directoryHint: .isDirectory)
        )
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

    func clear() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
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
