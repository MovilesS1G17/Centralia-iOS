import Foundation
import Testing

@testable import Centralia

// MARK: - Test doubles

private struct FakeTokenStore: AuthenticationTokenStore {
    func accessToken() throws -> String? { "test-token" }
    func save(accessToken: String) throws {}
    func clearAccessToken() throws {}
}

/// Stubs every request with a canned (status, headers, body) response and
/// records the requests made, so `APISearchRepository` can be exercised
/// without touching the network.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var headers: [String: String] = [:]
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: Self.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func makeClient() -> APILibraryClient {
    APILibraryClient(
        configuration: APIConfiguration(baseURL: URL(string: "https://centralia.test")!),
        session: stubbedSession(),
        tokenStore: FakeTokenStore()
    )
}

// MARK: - APISearchRepository

struct APISearchRepositoryTests {
    @Test func searchSendsDeviceAndPlatformHeadersAndQueryParams() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["X-Total-Count": "1"]
        StubURLProtocol.body = Data("""
        [{
            "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "source_url": "https://www.tiktok.com/@chef.maria/video/1",
            "platform": "tiktok",
            "creator": "chef.maria",
            "duration_seconds": 10,
            "source_caption": null,
            "transcript": null,
            "extracted_on_screen_text": null,
            "generated_summary": null,
            "custom_title": null,
            "folder_id": null,
            "tags": [],
            "note": null,
            "saved_at": "2026-09-28T14:32:00Z",
            "analysis_status": "completed"
        }]
        """.utf8)

        let repository = APISearchRepository(client: makeClient())
        let result = try await repository.search(
            query: "pasta", platform: .tiktok, creator: nil,
            folderID: nil, tag: nil, limit: nil, offset: 0
        )

        #expect(result.videos.count == 1)
        #expect(result.totalCount == 1)
        #expect(result.videos[0].creator == "chef.maria")

        let request = StubURLProtocol.lastRequest
        #expect(request?.value(forHTTPHeaderField: "X-Client-Platform") == "ios")
        #expect(request?.value(forHTTPHeaderField: "X-Device-Model")?.isEmpty == false)
        let url = request?.url?.absoluteString ?? ""
        #expect(url.contains("query=pasta"))
        #expect(url.contains("platform=tiktok"))
    }

    @Test func searchFallsBackToVideoCountWhenTotalCountHeaderMissing() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data("[]".utf8)

        let repository = APISearchRepository(client: makeClient())
        let result = try await repository.search(
            query: nil, platform: nil, creator: nil,
            folderID: nil, tag: nil, limit: nil, offset: 0
        )

        #expect(result.videos.isEmpty)
        #expect(result.totalCount == 0)
    }

    @Test func searchSurfacesServerErrorsAsCatchableErrors() async throws {
        StubURLProtocol.statusCode = 500
        StubURLProtocol.headers = [:]
        StubURLProtocol.body = Data("""
        {"detail": "boom"}
        """.utf8)

        let repository = APISearchRepository(client: makeClient())
        await #expect(throws: Error.self) {
            _ = try await repository.search(
                query: nil, platform: nil, creator: nil,
                folderID: nil, tag: nil, limit: nil, offset: 0
            )
        }
    }
}

// MARK: - SearchViewModel + search repository

private final class FakeSearchRepository: SearchRepository, @unchecked Sendable {
    var result: Result<SearchResult, Error> = .success(SearchResult(videos: [], totalCount: 0))
    private(set) var reportedEvents: [(durationMs: Int, resultCount: Int, filterCount: Int)] = []
    private(set) var searchCallCount = 0

    func search(
        query: String?, platform: VideoPlatform?, creator: String?,
        folderID: UUID?, tag: String?, limit: Int?, offset: Int
    ) async throws -> SearchResult {
        searchCallCount += 1
        return try result.get()
    }

    func reportSearchCompleted(durationMs: Int, resultCount: Int, filterCount: Int) {
        reportedEvents.append((durationMs, resultCount, filterCount))
    }
}

private func makeViewModel(
    libraryRepository: MockLibraryRepository,
    searchRepository: FakeSearchRepository,
    store: MockDataStore
) -> SearchViewModel {
    SearchViewModel(
        videoRepository: libraryRepository,
        folderRepository: libraryRepository,
        searchRepository: searchRepository,
        searchHistoryRepository: MockSearchHistoryRepository(
            store: store, filename: "vm-history-\(UUID().uuidString).json"
        )
    )
}

struct SearchViewModelSearchTests {
    @Test func selectingAFilterRunsASearchAndReportsLatency() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MockDataStore(directoryURL: directory)
        let libraryRepository = MockLibraryRepository(store: store, filename: "vm-search.json")

        let fake = FakeSearchRepository()
        fake.result = .success(SearchResult(videos: [], totalCount: 3))

        let viewModel = makeViewModel(
            libraryRepository: libraryRepository, searchRepository: fake, store: store
        )
        await viewModel.load()

        viewModel.selectPlatform(.tiktok)
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.state == .loaded)
        #expect(fake.searchCallCount == 1)
        #expect(fake.reportedEvents.count == 1)
        #expect(fake.reportedEvents[0].resultCount == 3)
        #expect(fake.reportedEvents[0].filterCount == 1)
    }

    @Test func searchWithNoActiveFiltersDoesNotReportTelemetry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MockDataStore(directoryURL: directory)
        let libraryRepository = MockLibraryRepository(store: store, filename: "vm-search-2.json")

        let fake = FakeSearchRepository()
        fake.result = .success(SearchResult(videos: [], totalCount: 0))

        let viewModel = makeViewModel(
            libraryRepository: libraryRepository, searchRepository: fake, store: store
        )
        await viewModel.load()

        viewModel.performSearch()
        try await Task.sleep(for: .milliseconds(50))

        #expect(fake.reportedEvents.isEmpty)
    }

    @Test func failedSearchShowsRetryableErrorAndRetryRepeatsTheSearch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MockDataStore(directoryURL: directory)
        let libraryRepository = MockLibraryRepository(store: store, filename: "vm-search-3.json")

        let fake = FakeSearchRepository()
        fake.result = .failure(URLError(.notConnectedToInternet))

        let viewModel = makeViewModel(
            libraryRepository: libraryRepository, searchRepository: fake, store: store
        )
        await viewModel.load()

        viewModel.selectCreator("chef.maria")
        try await Task.sleep(for: .milliseconds(50))

        guard case .failed = viewModel.state else {
            Issue.record("Expected a failed state after a search error")
            return
        }
        #expect(fake.searchCallCount == 1)

        fake.result = .success(SearchResult(videos: [], totalCount: 0))
        await viewModel.retry()
        try await Task.sleep(for: .milliseconds(50))

        #expect(fake.searchCallCount == 2)
        #expect(viewModel.state == .loaded)
    }
}
