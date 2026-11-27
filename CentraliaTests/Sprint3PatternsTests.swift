import Foundation
import Testing
@testable import Centralia

/// One pattern per member (Sprint 3). Same cases as `Sprint3PatternsTest.kt` on Android.
@MainActor
struct Sprint3PatternsTests {
    private func video(_ title: String) -> VideoItem {
        VideoItem(
            id: UUID(),
            sourceURL: URL(string: "https://www.tiktok.com/@x/video/\(UUID().uuidString)")!,
            platform: .tiktok,
            creator: "@x",
            durationSeconds: 30,
            sourceCaption: nil,
            transcript: nil,
            extractedOnScreenText: nil,
            generatedSummary: nil,
            customTitle: title,
            folderID: nil,
            tags: [],
            note: nil,
            savedAt: .now,
            analysisStatus: .completed
        )
    }

    // ---- David · caching: hand-written LRU for search results

    @Test func lruEvictsTheLeastRecentlyUsedEntry() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        #expect(cache.value(for: "a") == 1) // "a" is now the most recent
        cache.insert(3, for: "c")           // evicts "b"
        #expect(cache.value(for: "b") == nil)
        #expect(cache.keysInUseOrder == ["a", "c"])
        cache.insert(10, for: "a")          // update keeps one entry
        #expect(cache.count == 2 && cache.value(for: "a") == 10)
    }

    // ---- David · local storage: Core Data "Recently viewed"

    @Test func coreDataRecordsCountsAndOrdersViews() async {
        let store = CoreDataRecentlyViewedStore(inMemory: true)
        let a = video("A")
        let b = video("B")
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        await store.record(RecentlyViewedEntry(video: a, at: start))
        await store.record(RecentlyViewedEntry(video: b, at: start.addingTimeInterval(60)))
        await store.record(RecentlyViewedEntry(video: a, at: start.addingTimeInterval(120)))

        let recent = await store.recent(limit: 10)
        #expect(recent.map(\.videoID) == [a.id, b.id])
        #expect(recent.first?.viewCount == 2)

        // A short deleted from the library drops out of the row.
        #expect(RecentlyViewed.videos(for: recent, in: [b]).map(\.video.id) == [b.id])

        await store.remove(videoID: b.id)
        #expect(await store.recent(limit: 10).map(\.videoID) == [a.id])
        await store.clear()
        #expect(await store.recent(limit: 10).isEmpty)
    }

    @Test func coreDataKeepsAtMostFiftyViews() async {
        let store = CoreDataRecentlyViewedStore(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<60 {
            await store.record(RecentlyViewedEntry(video: video("Short \(index)"), at: start.addingTimeInterval(Double(index))))
        }
        #expect(await store.recent(limit: 100).count == RecentlyViewed.maxStored)
        #expect(await store.recent(limit: RecentlyViewed.shownInLibrary).first?.title == "Short 59")
    }

    // ---- Gustavo · local storage: remembered email (Keychain on the phone)

    @Test func rememberedEmailPrefillsTheSignInForm() async {
        let store = InMemoryRememberedEmailStore()
        let first = LogInViewModel(repository: MockAuthenticationRepository(delay: .zero), rememberedEmail: store)
        first.email = "ana@example.com"
        first.password = "valid-password"
        _ = await first.logIn()
        #expect(store.email() == "ana@example.com")

        let next = LogInViewModel(repository: MockAuthenticationRepository(delay: .zero), rememberedEmail: store)
        #expect(next.email == "ana@example.com")

        next.rememberEmail = false
        next.password = "valid-password"
        _ = await next.logIn()
        #expect(store.email() == nil)
    }

    // ---- Gustavo · multithreading: task-group prefetch

    @Test func prefetchWithNothingToDownloadReturnsAtOnce() async {
        #expect(await CoverImageLoader.shared.prefetch([]) == 0)
    }
}
