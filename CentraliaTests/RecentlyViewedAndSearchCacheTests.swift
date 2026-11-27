import Foundation
import Testing
@testable import Centralia

@MainActor
struct RecentlyViewedAndSearchCacheTests {
    @Test func lruEvictsTheLeastRecentlyUsedEntry() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        #expect(cache.value(for: "a") == 1)
        cache.insert(3, for: "c")
        #expect(cache.value(for: "b") == nil)
        #expect(cache.keysInUseOrder == ["a", "c"])
        cache.insert(10, for: "a")
        #expect(cache.count == 2)
        #expect(cache.value(for: "a") == 10)
    }

    @Test func coreDataRecordsCountsAndOrdersViews() async {
        let store = CoreDataRecentlyViewedStore(inMemory: true)
        let first = LibraryFixtures.video()
        let second = LibraryFixtures.video()
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        await store.record(RecentlyViewedEntry(video: first, at: start))
        await store.record(RecentlyViewedEntry(video: second, at: start.addingTimeInterval(60)))
        await store.record(RecentlyViewedEntry(video: first, at: start.addingTimeInterval(120)))

        let recent = await store.recent(limit: 10)
        #expect(recent.map(\.videoID) == [first.id, second.id])
        #expect(recent.first?.viewCount == 2)
        #expect(RecentlyViewed.videos(for: recent, in: [second]).map(\.video.id) == [second.id])

        await store.remove(videoID: second.id)
        #expect(await store.recent(limit: 10).map(\.videoID) == [first.id])
        await store.clear()
        #expect(await store.recent(limit: 10).isEmpty)
    }

    @Test func coreDataPersistsOnlyTheFiftyMostRecentShorts() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "RecentlyViewed.sqlite")
        let writer = CoreDataRecentlyViewedStore(storeURL: url)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let videos = (0..<60).map { _ in LibraryFixtures.video() }
        for (index, video) in videos.enumerated() {
            await writer.record(RecentlyViewedEntry(video: video, at: start.addingTimeInterval(Double(index))))
        }

        let reader = CoreDataRecentlyViewedStore(storeURL: url)
        #expect(await reader.recent(limit: 100).map(\.videoID) == videos.suffix(50).reversed().map(\.id))
        #expect(await reader.recent(limit: RecentlyViewed.shownInLibrary).count == 10)
    }

    @Test func nextSessionReadsAfterSignOutCleanup() async {
        let history = RecentlyViewedHistory(store: InMemoryRecentlyViewedStore())
        await history.record(RecentlyViewedEntry(video: LibraryFixtures.video()))
        #expect(await history.recent(limit: 10).count == 1)

        history.clear()
        #expect(await history.recent(limit: 10).isEmpty)
    }
}
