import Foundation
import Testing
@testable import Centralia

struct RediscoverTests {
    @Test func parallelPicksFollowTheSameEligibilityAndOrderAsSerialPicks() async {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = makeVideo(daysAgo: 30, now: now)
        let oldAndUnopened = makeVideo(daysAgo: 7, now: now)
        let recent = makeVideo(daysAgo: 6, now: now)
        let reopened = makeVideo(daysAgo: 30, now: now)
        let dismissed = makeVideo(daysAgo: 30, now: now)
        let videos = [old, oldAndUnopened, recent, reopened, dismissed]
        let history = [
            old.id: now.addingTimeInterval(-14 * 86_400),
            reopened.id: now.addingTimeInterval(-13 * 86_400)
        ]

        let picks = await Rediscover.pickInParallel(
            videos, lastViewed: history, dismissed: [dismissed.id], now: now
        )

        #expect(Set(picks.map(\.videoID)) == [old.id, oldAndUnopened.id])
        #expect(picks == Rediscover.pick(videos, lastViewed: history, dismissed: [dismissed.id], now: now))
    }

    @Test func dismissalsPersistExpireAndStayWithinTheirAccount() throws {
        let name = "rediscover-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let account = UUID()
        let video = UUID()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let firstStore = UserDefaultsRediscoverDismissals(accountID: account, defaults: defaults)
        firstStore.dismiss(video, at: now)

        let reopened = UserDefaultsRediscoverDismissals(accountID: account, defaults: defaults)
        let otherAccount = UserDefaultsRediscoverDismissals(accountID: UUID(), defaults: defaults)
        #expect(reopened.active(now: now) == [video])
        #expect(otherAccount.active(now: now).isEmpty)
        #expect(reopened.active(now: now.addingTimeInterval(30 * 86_400)).isEmpty)
    }

    private func makeVideo(daysAgo: Int, now: Date) -> VideoFacts {
        VideoFacts(
            id: UUID(), savedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
            creator: "creator", platformRaw: "tiktok", folderID: nil, tags: []
        )
    }
}
