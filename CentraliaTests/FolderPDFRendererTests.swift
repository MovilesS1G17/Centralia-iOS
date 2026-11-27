import Foundation
import PDFKit
import Testing
@testable import Centralia

@MainActor
struct FolderPDFRendererTests {
    @Test func exportsAllShortsInDateOrderWithClickableSourceLinks() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shorts = try (1...7).map(makeShort)
        var completedPages: [Int] = []

        let file = try await FolderPDFRenderer.render(
            folderName: "Design / Travel",
            shorts: shorts,
            directory: directory,
            cachedCover: { _ in
                #expect(!Self.isMainThread())
                return nil
            },
            onProgress: { completedPages.append($0.completedPages) }
        )

        #expect(file.url.pathExtension == "pdf")
        let document = try #require(PDFDocument(url: file.url))
        #expect(document.pageCount == 2)
        #expect(completedPages == [0, 1, 2])
        let firstPage = try #require(document.page(at: 0))
        let lastPage = try #require(document.page(at: 1))
        #expect(firstPage.string?.contains("Short 07") == true)
        #expect(firstPage.string?.contains("Short 01") == false)
        #expect(lastPage.string?.contains("Short 01") == true)
        let urls = firstPage.annotations.compactMap { ($0.action as? PDFActionURL)?.url }
        #expect(Set(urls) == Set(shorts.dropFirst().map(\.sourceURL)))
    }

    @Test func cancellationRemovesTheUnfinishedPDF() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let shorts = try (1...7).map(makeShort)

        let task = Task {
            try await FolderPDFRenderer.render(
                folderName: "Design",
                shorts: shorts,
                directory: directory,
                onProgress: { progress in
                    if progress.completedPages == 1 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.isEmpty)
    }

    private func makeShort(_ index: Int) throws -> FolderPDFRenderer.Short {
        let url = try #require(URL(string: "https://www.youtube.com/shorts/centralia\(index)"))
        return FolderPDFRenderer.Short(
            title: String(format: "Short %02d", index),
            creator: "@centralia",
            platform: "YouTube Short",
            savedAt: Date(timeIntervalSince1970: Double(index)),
            sourceURL: url,
            coverURL: URL(string: "https://i.ytimg.com/vi/centralia\(index)/hqdefault.jpg")
        )
    }

    private nonisolated static func isMainThread() -> Bool {
        Thread.isMainThread
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
