import Foundation
import Testing
@testable import Centralia

struct CreatorsTests {
    @Test func parallelGroupingMatchesSequentialGroupingAcrossPlatforms() async {
        let older = fact(creator: "@Creator", platform: "tiktok", savedAt: 1)
        let newer = fact(creator: "creator", platform: "instagramReel", savedAt: 2)
        let other = fact(creator: "Other", platform: "youtubeShort", savedAt: 3)
        let unknown = fact(creator: "@", platform: "youtubeShort", savedAt: 4)
        let videos = [older, newer, other, unknown]

        let parallel = await Creators.groupInParallel(videos)

        #expect(parallel == Creators.group(videos))
        #expect(parallel.map(\.id) == ["creator", "other"])
        #expect(parallel.first?.videoIDs == [newer.id, older.id])
        #expect(parallel.first?.platformsRaw == ["tiktok", "instagramReel"])
    }

    @Test func changedPlatformOrSaveDateInvalidatesTheCacheKey() {
        let video = fact(creator: "Creator", platform: "tiktok", savedAt: 1)
        let moved = fact(id: video.id, creator: "Creator", platform: "instagramReel", savedAt: 1)
        let updated = fact(id: video.id, creator: "Creator", platform: "tiktok", savedAt: 2)
        let cache = CreatorsCache()
        let key = Creators.fingerprint([video])
        let grouped = Creators.group([video])
        cache.insert(grouped, for: key)

        #expect(cache.value(for: key) == grouped)
        #expect(cache.value(for: Creators.fingerprint([moved])) == nil)
        #expect(cache.value(for: Creators.fingerprint([updated])) == nil)
    }

    private func fact(id: UUID = UUID(), creator: String, platform: String, savedAt: TimeInterval) -> VideoFacts {
        VideoFacts(
            id: id, savedAt: Date(timeIntervalSince1970: savedAt), creator: creator,
            platformRaw: platform, folderID: nil, tags: []
        )
    }
}
