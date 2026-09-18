import Foundation

actor MockLibraryRepository: VideoItemRepository, FolderRepository {
    private struct Snapshot: Codable, Sendable {
        let schemaVersion: Int
        var videos: [VideoItem]
        var folders: [LibraryFolder]
    }

    private let store: MockDataStore
    private let filename: String

    init(
        store: MockDataStore = MockDataStore(),
        filename: String = "library-v1.json"
    ) {
        self.store = store
        self.filename = filename
    }

    func videos() async throws -> [VideoItem] {
        try await snapshot().videos.sorted { $0.savedAt > $1.savedAt }
    }

    func folders() async throws -> [LibraryFolder] {
        try await snapshot().folders.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func deleteVideo(id: UUID) async throws {
        var value = try await snapshot()
        value.videos.removeAll { $0.id == id }
        try await store.save(value, to: filename)
    }

    func restoreVideo(_ video: VideoItem) async throws {
        var value = try await snapshot()
        value.videos.removeAll { $0.id == video.id }
        value.videos.append(video)
        try await store.save(value, to: filename)
    }

    func moveVideo(id: UUID, to folderID: UUID?) async throws {
        var value = try await snapshot()

        guard let index = value.videos.firstIndex(where: { $0.id == id }) else {
            return
        }

        value.videos[index].folderID = folderID
        try await store.save(value, to: filename)
    }

    private func snapshot() async throws -> Snapshot {
        try await store.load(Snapshot.self, from: filename, seed: Self.seed)
    }

    private static let seed: Snapshot = {
        let spaces = LibraryFolder(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
            name: "Spaces",
            symbolName: "house"
        )
        let design = LibraryFolder(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
            name: "Design",
            symbolName: "paintpalette"
        )
        let recipes = LibraryFolder(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000003")!,
            name: "Recipes",
            symbolName: "fork.knife"
        )
        let wellbeing = LibraryFolder(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000004")!,
            name: "Wellbeing",
            symbolName: "sun.max"
        )

        let baseDate = Date(timeIntervalSince1970: 1_789_166_400)
        let videos = [
            VideoItem(
                id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
                sourceURL: URL(string: "https://www.tiktok.com/@roomreset/video/1")!,
                platform: .tiktok,
                creator: "@roomreset",
                durationSeconds: 28,
                sourceCaption: "Wait for the final result.",
                transcript: "Use vertical storage and keep the desk close to natural light in a small studio.",
                extractedOnScreenText: "small studio reset",
                generatedSummary: "Tiny studio ideas",
                customTitle: nil,
                folderID: spaces.id,
                tags: ["studio", "organization", "interiors"],
                note: nil,
                savedAt: baseDate,
                analysisStatus: .completed
            ),
            VideoItem(
                id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
                sourceURL: URL(string: "https://www.instagram.com/reel/centralia-colour")!,
                platform: .instagramReel,
                creator: "@studiomarta",
                durationSeconds: 41,
                sourceCaption: "The third one changed everything.",
                transcript: "Choose one dominant color, one supporting color, and one small accent color.",
                extractedOnScreenText: "three colour rule",
                generatedSummary: "Three color rules",
                customTitle: nil,
                folderID: design.id,
                tags: ["color", "design", "visual identity"],
                note: nil,
                savedAt: baseDate.addingTimeInterval(-3_600),
                analysisStatus: .completed
            ),
            VideoItem(
                id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
                sourceURL: URL(string: "https://www.youtube.com/shorts/centralia-pasta")!,
                platform: .youtubeShort,
                creator: "@quickplate",
                durationSeconds: 54,
                sourceCaption: "Dinner sorted.",
                transcript: "Boil the pasta while the tomatoes, garlic, and olive oil cook in the same pan.",
                extractedOnScreenText: "20 minute pasta",
                generatedSummary: "Pasta in 20 minutes",
                customTitle: nil,
                folderID: recipes.id,
                tags: ["pasta", "dinner", "quick recipes"],
                note: "Try this on Thursday.",
                savedAt: baseDate.addingTimeInterval(-7_200),
                analysisStatus: .completed
            ),
            VideoItem(
                id: UUID(uuidString: "10000000-0000-4000-8000-000000000004")!,
                sourceURL: URL(string: "https://www.tiktok.com/@slowmornings/video/4")!,
                platform: .tiktok,
                creator: "@slowmornings",
                durationSeconds: 22,
                sourceCaption: "Needed this today.",
                transcript: nil,
                extractedOnScreenText: "a slower morning routine",
                generatedSummary: "A calmer morning",
                customTitle: nil,
                folderID: wellbeing.id,
                tags: ["morning", "routine", "wellbeing"],
                note: nil,
                savedAt: baseDate.addingTimeInterval(-10_800),
                analysisStatus: .completed
            ),
            VideoItem(
                id: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!,
                sourceURL: URL(string: "https://www.instagram.com/reel/centralia-ceramics")!,
                platform: .instagramReel,
                creator: "@softforms",
                durationSeconds: 36,
                sourceCaption: "One more for the shelf.",
                transcript: "Center the clay before opening the form and keep both elbows anchored.",
                extractedOnScreenText: "wheel throwing basics",
                generatedSummary: "Centering clay on the wheel",
                customTitle: nil,
                folderID: design.id,
                tags: ["ceramics", "craft", "tutorial"],
                note: nil,
                savedAt: baseDate.addingTimeInterval(-14_400),
                analysisStatus: .completed
            ),
            VideoItem(
                id: UUID(uuidString: "10000000-0000-4000-8000-000000000006")!,
                sourceURL: URL(string: "https://www.youtube.com/shorts/centralia-swiftui")!,
                platform: .youtubeShort,
                creator: "@swiftminute",
                durationSeconds: 48,
                sourceCaption: "This transition feels so much better.",
                transcript: "Use a matched geometry effect to preserve spatial continuity between both SwiftUI states.",
                extractedOnScreenText: "matchedGeometryEffect",
                generatedSummary: "Smoother SwiftUI transitions",
                customTitle: nil,
                folderID: nil,
                tags: ["SwiftUI", "animation", "iOS"],
                note: nil,
                savedAt: baseDate.addingTimeInterval(-18_000),
                analysisStatus: .completed
            )
        ]

        return Snapshot(
            schemaVersion: 1,
            videos: videos,
            folders: [spaces, design, recipes, wellbeing]
        )
    }()
}
