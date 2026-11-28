import Foundation
import Testing
@testable import Centralia

@MainActor
struct Sprint4FeaturesTests {
    @Test func folderCountsFollowChangesToTheLibrary() async throws {
        let first = LibraryFolder(id: UUID(), name: "First", symbolName: "folder")
        let second = LibraryFolder(id: UUID(), name: "Second", symbolName: "folder")
        let empty = LibraryFolder(id: UUID(), name: "Empty", symbolName: "folder")
        let video = LibraryFixtures.video(folderID: first.id)
        let unorganized = LibraryFixtures.video()
        let library = V3SimulatedLibrary(videos: [video, unorganized], folders: [first, second, empty])
        let model = LibraryViewModel(videoRepository: library, folderRepository: library)

        await model.load()
        #expect(model.folderVideoCounts == [first.id: 1])
        #expect(model.folderVideoCounts[empty.id, default: 0] == 0)

        await model.move(video, to: second.id)
        #expect(model.folderVideoCounts == [second.id: 1])

        let moved = try #require(model.videos.first { $0.id == video.id })
        await model.delete(moved)
        #expect(model.folderVideoCounts.isEmpty)

        await model.undoDelete()
        #expect(model.folderVideoCounts == [second.id: 1])
    }
}
