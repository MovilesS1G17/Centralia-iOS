import Foundation
import Testing
@testable import Centralia

struct WatchLaterTests {
    @Test func queueOrderAndWatchedStateSurviveReopeningTheDatabase() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "WatchLater.sqlite")
        let account = UUID()
        let store = CoreDataWatchLaterStore(accountID: account, storeURL: file)
        let first = UUID()
        let second = UUID()
        let date = Date(timeIntervalSince1970: 2_000_000_000)

        #expect(await store.add(videoID: first, title: "First", creator: "Creator", at: date))
        #expect(await store.add(videoID: second, title: "Second", creator: "Creator", at: date))
        #expect(await !store.add(videoID: first, title: "First", creator: "Creator", at: date))
        await store.move(second, by: -1)
        #expect(await store.entries().map(\.videoID) == [second, first])
        #expect(await store.markWatched(second, at: date)?.isWatched == false)

        let reopened = CoreDataWatchLaterStore(accountID: account, storeURL: file)
        let entries = await reopened.entries()
        #expect(entries.map(\.videoID) == [first, second])
        #expect(entries.last?.isWatched == true)
        await reopened.clearWatched()
        #expect(await reopened.entries().map(\.videoID) == [first])
    }
}
