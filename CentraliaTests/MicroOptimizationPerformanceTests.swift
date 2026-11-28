import Foundation
import XCTest
@testable import Centralia

@MainActor
final class MicroOptimizationPerformanceTests: XCTestCase {
    private let keystrokes = (1...9).map { VideoSearchCriteria(text: String("pasta bea".prefix($0))) }

    func testSearchKeystrokesBefore() {
        let (videos, folders) = library()
        var matches = 0
        measure {
            matches = keystrokes.reduce(0) {
                $0 + VideoSearch.filter(videos, criteria: $1, folderNames: folders).count
            }
        }
        XCTAssertGreaterThan(matches, 0)
    }

    func testSearchKeystrokesAfter() {
        let (videos, folders) = library()
        let index = VideoSearchIndex(videos, folderNames: folders)
        var matches = 0
        measure {
            matches = keystrokes.reduce(0) { $0 + index.filter(criteria: $1).count }
        }
        XCTAssertGreaterThan(matches, 0)
    }

    func testIndexedSearchPreservesLocalizedMatchingAndFilters() {
        let folder = UUID()
        let videos = [
            LibraryFixtures.video(creator: "@café", caption: "Lunch", transcript: "Crème brûlée", folderID: folder, tags: ["Food"]),
            LibraryFixtures.video(creator: "@maker", caption: "ß", transcript: "カフェ", tags: ["Travel"]),
            LibraryFixtures.video(creator: "@coder", caption: "🧑🏽‍💻", transcript: "ﬃ")
        ]
        let names = [folder: "Recetas"]
        let index = VideoSearchIndex(videos, folderNames: names)
        let criteria: [VideoSearchCriteria] = [
            .init(text: "CAFE crema"), .init(text: "creme recetas"), .init(text: "CAFE lunch", tags: ["food"]),
            .init(text: "s"), .init(text: "ss"), .init(text: "ｶﾌｪ"), .init(text: "🧑"), .init(text: "fi"),
            .init(text: "   ", folder: .unorganized), .init(text: "lunch", platform: .youtubeShort)
        ]
        for query in criteria {
            XCTAssertEqual(index.filter(criteria: query), VideoSearch.filter(videos, criteria: query, folderNames: names), query.text)
        }
    }

    func testSearchUpdatesTheIndexAfterVideoEdits() async {
        let video = LibraryFixtures.video(customTitle: "Before")
        let library = V3SimulatedLibrary(videos: [video])
        let model = SearchViewModel(videoRepository: library, folderRepository: library, searchHistoryRepository: EmptySearchHistory())
        await model.load()

        model.query = "before"
        XCTAssertEqual(model.filteredVideos.map(\.id), [video.id])
        var edited = video
        edited.customTitle = "After"
        model.apply(edited)
        XCTAssertTrue(model.filteredVideos.isEmpty)
        model.query = "after"
        XCTAssertEqual(model.filteredVideos, [edited])
    }

    func testDateParsingBefore() {
        measureDateParsing { value in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
    }

    func testDateParsingWithReusedFormatters() {
        measureDateParsing(APIDateFormatters.parse)
    }

    private func measureDateParsing(_ parse: (String) -> Date?) {
        let timestamps = (0..<1_000).map { index in
            index.isMultiple(of: 2) ? "2026-11-26T15:00:00.250Z" : "2026-11-26T15:00:00Z"
        }
        var parsed = [Date]()
        measure {
            parsed = timestamps.compactMap(parse)
        }
        XCTAssertEqual(parsed.count, timestamps.count)
    }

    func testFolderCountsBefore() {
        let (folders, videos) = folderCountFixture()
        var total = 0
        measure {
            total = folders.reduce(0) { sum, folder in
                sum + videos.count { $0.folderID == folder }
            }
        }
        XCTAssertEqual(total, 750)
    }

    func testFolderCountsInOnePass() {
        let (folders, videos) = folderCountFixture()
        var total = 0
        measure {
            let counts = LibraryViewModel.countByFolder(videos)
            total = folders.reduce(0) { $0 + counts[$1, default: 0] }
        }
        XCTAssertEqual(total, 750)
    }

    private func folderCountFixture() -> (folders: [UUID], videos: [VideoItem]) {
        let folders = (0..<40).map { _ in UUID() }
        let videos = (0..<1_000).map { index in
            LibraryFixtures.video(folderID: index.isMultiple(of: 4) ? nil : folders[index % folders.count])
        }
        return (folders, videos)
    }

    /// The same 1,000 shorts and query prefixes run against both implementations.
    private func library() -> (videos: [VideoItem], folders: [UUID: String]) {
        let words = ["pasta", "workout", "beach", "design", "swiftui", "morning", "routine", "crème",
                     "brûlée", "jalapeño", "interiors", "tips", "budget", "camera", "street", "food"]
        let folderIDs = (0..<6).map { _ in UUID() }
        let folders = Dictionary(uniqueKeysWithValues: zip(folderIDs, ["Recipes", "Gym", "Travel", "Design", "Tech", "Café"]))

        func phrase(_ seed: Int, length: Int) -> String {
            (0..<length).map { words[(seed + $0 * 7 + seed / 13) % words.count] }.joined(separator: " ")
        }

        let videos = (0..<1_000).map { index in
            LibraryFixtures.video(
                url: "https://www.tiktok.com/@x/video/\(index)",
                creator: "@creator\(index % 60)",
                caption: phrase(index, length: 6),
                transcript: phrase(index / 2, length: 20),
                folderID: index.isMultiple(of: 2) ? folderIDs[index % folderIDs.count] : nil,
                tags: [words[index % words.count]]
            )
        }
        return (videos, folders)
    }
}

private struct EmptySearchHistory: SearchHistoryRepository {
    func recentSearches() async throws -> [String] { [] }
    func recordSearch(_ query: String) async throws {}
    func clearSearchHistory() async throws {}
}
