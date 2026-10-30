import Foundation
import Testing
@testable import Centralia

/// Sprint 3: eventual connectivity, local storage and caching. Same rules as
/// `OfflineFirstTest.kt` in the Android app.
@MainActor
struct OfflineFirstTests {
    private let id = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func action(_ kind: PendingAction.Kind, videoID: UUID? = nil) -> PendingAction {
        PendingAction(videoID: videoID ?? id, queuedAt: now, kind: kind)
    }

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "centralia-offline-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    // MARK: Outbox rules

    @Test func undoingADeleteThatNeverReachedTheServerCancelsBoth() {
        let queued = PendingAction.enqueue(action(.delete), into: [])
        #expect(PendingAction.enqueue(action(.restore(method: .shake)), into: queued).isEmpty)
    }

    @Test func undoingADeleteThatAlreadySyncedIsQueued() {
        let queued = PendingAction.enqueue(action(.restore(method: .button)), into: [])
        #expect(queued == [action(.restore(method: .button))])
    }

    @Test func aNewerEditOfTheSameKindReplacesTheOlderOne() {
        var queue = PendingAction.enqueue(action(.tags(["a"])), into: [])
        queue = PendingAction.enqueue(action(.note("hi")), into: queue)
        queue = PendingAction.enqueue(action(.tags(["b"])), into: queue)
        queue = PendingAction.enqueue(action(.tags(["other"]), videoID: UUID()), into: queue)
        #expect(queue.count == 3)
        #expect(queue.filter { $0.videoID == id }.map(\.kind) == [.note("hi"), .tags(["b"])])
    }

    @Test func queuedChangesApplyToTheLocalCopy() {
        let folder = UUID()
        let video = LibraryFixtures.video(id: id)
        let other = LibraryFixtures.video(url: "https://www.tiktok.com/@maker/video/2")
        let moved = action(.move(folderID: folder)).apply(to: [video, other])
        #expect(moved.first?.folderID == folder)
        #expect(action(.note("later")).apply(to: [video]).first?.note == "later")
        #expect(action(.delete).apply(to: [video, other]) == [other])
    }

    // MARK: Local storage

    @Test func theOutboxSurvivesClosingTheApp() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = PendingActionQueue(directory: directory) { _ in }
        await first.enqueue(action(.tags(["pasta"])))
        await first.enqueue(action(.move(folderID: nil)))

        let reopened = PendingActionQueue(directory: directory)
        #expect(await reopened.all() == [action(.tags(["pasta"])), action(.move(folderID: nil))])
        await reopened.clear()
        #expect(await PendingActionQueue(directory: directory).all().isEmpty)
    }

    @Test func theLibraryCopyIsReadBackFromDisk() async {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let video = LibraryFixtures.video(id: id, tags: ["pasta"])
        await LocalLibraryStore(directory: directory).update { snapshot in
            var copy = snapshot
            copy.videos = [video]
            return copy
        }
        #expect(await LocalLibraryStore(directory: directory).read().videos.map(\.id) == [id])
    }

    // MARK: Caching

    @Test func playbackIsCachedForTenMinutesPerNetwork() {
        var clock = now
        let cache = LibraryMemoryCache(now: { clock })
        let playback = VideoPlayback(streamURL: nil, streamReady: false, expiresAt: nil, embedURL: nil)
        cache.store(playback, for: id, network: .wifi)

        #expect(cache.playback(for: id, network: .wifi) == playback)
        #expect(cache.playback(for: id, network: .cellular) == nil) // data saver answers differently
        clock = now.addingTimeInterval(11 * 60)
        #expect(cache.playback(for: id, network: .wifi) == nil)
    }

    // MARK: Banner

    @Test func theBannerSaysWhatWorksOfflineAndWhatWillSync() {
        #expect(OfflineBanner.text(isOnline: false, pendingChanges: 0) == "You're offline. Showing your saved library.")
        #expect(
            OfflineBanner.text(isOnline: false, pendingChanges: 1)
                == "You're offline. Showing your saved library · 1 change will sync when you're back online."
        )
        #expect(OfflineBanner.text(isOnline: true, pendingChanges: 3) == "Back online · syncing 3 changes…")
    }

    @Test func offlineMessagesNameTheAction() {
        #expect(
            OfflineError.needsConnection("Saving a short").errorDescription
                == "You're offline. Saving a short needs a connection. Try again when you're back online."
        )
        #expect(FeatureError.code(for: OfflineError.needsConnection("x")) == "offline")
    }
}
