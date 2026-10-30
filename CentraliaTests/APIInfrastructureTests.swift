import Foundation
import Testing
@testable import Centralia

private struct TestTokenStore: AuthenticationTokenStore {
    let token: String?

    func accessToken() throws -> String? { token }
    func save(accessToken _: String) throws {}
    func clearAccessToken() throws {}
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))!

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data) = Self.handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}

@Suite(.serialized)
@MainActor
struct APIInfrastructureTests {
    private func client(token: String? = "test-token") -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.example.test")),
            session: URLSession(configuration: configuration),
            tokenStore: TestTokenStore(token: token)
        )
    }

    @Test func authenticatedRequestSendsV3HeadersAndDecodesProfile() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/me")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(request.value(forHTTPHeaderField: "X-Client-Platform") == "ios")
            return (200, Data(#"{"id":"11111111-1111-4111-8111-111111111111","displayName":"April","email":"april@example.test","membershipStatus":"centraliaMember"}"#.utf8))
        }

        let profile = try await client().request(UserProfileDTO.self, path: "/v1/me")
        #expect(profile.model.displayName == "April")
    }

    @Test func unauthenticatedLoginPreservesStructuredVerificationError() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/auth/login")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (403, Data(#"{"code":"email_not_verified","detail":"Confirm your email.","email":"april@example.test","retryAfter":45}"#.utf8))
        }

        do {
            _ = try await client().send("/v1/auth/login", method: "POST", authenticated: false)
            Issue.record("Expected a verification error")
        } catch APIClientError.server(let status, let code, _, let email, let retryAfter) {
            #expect(status == 403)
            #expect(code == "email_not_verified")
            #expect(email == "april@example.test")
            #expect(retryAfter == 45)
        }
    }

    @Test func registrationDoesNotCreateASessionBeforeVerification() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/auth/register")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try? JSONSerialization.jsonObject(with: requestBody(request)) as? [String: String]
            #expect(body?["email"] == "april@example.test")
            #expect(body?["password"] == "password123")
            #expect(body?["displayName"] == nil)
            return (202, Data(#"{"status":"verification_required","email":"april@example.test","resendAvailableIn":60}"#.utf8))
        }

        let repository = APIAuthenticationRepository(client: client(token: nil))
        do {
            _ = try await repository.createAccount(
                displayName: "April", email: "april@example.test", password: "password123"
            )
            Issue.record("Registration must not authenticate before email verification")
        } catch AuthenticationError.verificationRequired(let email, let wait) {
            #expect(email == "april@example.test")
            #expect(wait == 60)
        }
    }

    @Test func playbackResolvesOnlySignedPathsOnAPIOrigin() throws {
        let api = client()
        let playback = try api.decode(
            VideoPlaybackDTO.self,
            from: Data(#"{"streamURL":"/v1/streams/abc?expires=123&signature=xyz","streamReady":true,"expiresAt":"2026-10-02T12:00:00Z","embedURL":"https://www.youtube.com/embed/abc"}"#.utf8)
        )
        let model = try playback.model(configuration: api.configuration)
        #expect(model.streamURL?.absoluteString == "https://api.example.test/v1/streams/abc?expires=123&signature=xyz")
        #expect(model.streamReady)

        #expect(throws: APIClientError.self) {
            try api.configuration.streamURL(for: "https://other.example/v1/streams/abc")
        }
    }

    @Test func deleteAnswerCarriesTheShakeToUndoPopup() throws {
        let api = client()
        let deletion = try api.decode(
            VideoDeletionDTO.self,
            from: Data(#"{"videoID":"5f0c2a3e-1111-4222-8333-944455556666","deletedAt":"2026-10-28T14:00:00Z","undoExpiresAt":"2026-10-28T14:05:00Z","undoMessage":"If you want to undo the delete, just shake the phone."}"#.utf8)
        ).model
        #expect(deletion.videoID == UUID(uuidString: "5F0C2A3E-1111-4222-8333-944455556666"))
        #expect(deletion.undoMessage == "If you want to undo the delete, just shake the phone.")
        #expect(deletion.undoExpiresAt == ISO8601DateFormatter().date(from: "2026-10-28T14:05:00Z"))
    }

    @Test func offlineDeletesUseTheSameTextAndWindowAsTheBackend() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deletion = VideoDeletion.local(videoID: UUID(), now: now)
        #expect(deletion.undoMessage == VideoDeletion.defaultUndoMessage)
        #expect(deletion.undoExpiresAt == now.addingTimeInterval(300))
    }

    @Test func playbackSendsTheNetworkAndShowsDataSaver() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/videos/11111111-1111-4111-8111-111111111111/playback")
            #expect(request.url?.query == "network=cellular")
            return (200, Data(#"{"streamURL":null,"streamReady":false,"embedURL":"https://www.youtube.com/embed/abc","dataSaver":true,"notice":"You're on mobile data, so this short plays in data saver mode."}"#.utf8))
        }

        let repository = APIVideoPlaybackRepository(client: APILibraryClient(api: client()), network: { .cellular })
        let playback = try await repository.playback(for: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
        #expect(playback.dataSaver)
        #expect(playback.streamURL == nil)
        #expect(playback.notice == "You're on mobile data, so this short plays in data saver mode.")
    }

    @Test func networkTypeFollowsThePhonesConnection() {
        #expect(NetworkType.from(connected: false, wifiOrEthernet: true, cellular: true) == .offline)
        #expect(NetworkType.from(connected: true, wifiOrEthernet: true, cellular: true) == .wifi)
        #expect(NetworkType.from(connected: true, wifiOrEthernet: false, cellular: true) == .cellular)
        #expect(NetworkType.from(connected: true, wifiOrEthernet: false, cellular: false) == .unknown)
        #expect(NetworkType.allCases.map(\.rawValue) == ["wifi", "cellular", "offline", "unknown"])
    }

    @Test func missingBaseURLReturnsReadableError() throws {
        #expect(throws: APIClientError.self) {
            try APIConfiguration(baseURL: nil).endpoint(path: "/v1/me")
        }
    }

    @Test func analyticsUsesISODateAndScalarProperties() throws {
        let event = ClientAnalyticsEvent(
            name: "play_started",
            occurredAt: Date(timeIntervalSince1970: 1_759_406_400),
            properties: ["video_id": .text("abc"), "retry_count": .integer(2), "ready": .boolean(true)]
        )
        let data = try client().encode(event)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["occurredAt"] as? String)?.hasSuffix("Z") == true)
        let properties = try #require(json["properties"] as? [String: Any])
        #expect(properties["video_id"] as? String == "abc")
        #expect(properties["retry_count"] as? Int == 2)
        #expect(properties["ready"] as? Bool == true)
    }

    @Test func analyticsAcceptsEventsBeforeLogin() async throws {
        StubURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/analytics/events")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (202, Data(#"{"accepted":1,"rejected":0}"#.utf8))
        }
        let repository = APIAnalyticsRepository(client: client(token: nil))
        try await repository.record([
            ClientAnalyticsEvent(name: "screen_viewed", occurredAt: .now,
                                 properties: ["screen": .text("sign_up")])
        ])
    }

    // MARK: Sprint 3: eventual connectivity

    @Test func replayingAnOfflineDeleteSendsWhenItWasQueued() async throws {
        let id = UUID(uuidString: "5F0C2A3E-1111-4222-8333-944455556666")!
        var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            return (200, Data(#"{"videoID":"5f0c2a3e-1111-4222-8333-944455556666","deletedAt":"2026-10-28T14:00:00Z","undoExpiresAt":"2026-10-28T14:05:00Z","undoMessage":"x"}"#.utf8))
        }
        let queuedAt = ISO8601DateFormatter().date(from: "2026-10-28T13:58:30Z")!
        let repository = APIVideoItemRepository(client: APILibraryClient(api: client()))
        try await repository.replay(PendingAction(videoID: id, queuedAt: queuedAt, kind: .delete))

        #expect(seen?.httpMethod == "DELETE")
        #expect(seen?.url?.path == "/v1/videos/\(id)")
        #expect(seen?.value(forHTTPHeaderField: "X-Queued-At") == "2026-10-28T13:58:30.000Z")
    }

    @Test func replayingOfflineTagsSendsThePatch() async throws {
        var seen: URLRequest?
        var body = Data()
        StubURLProtocol.handler = { request in
            seen = request
            body = requestBody(request)
            return (200, Data("{}".utf8))
        }
        let repository = APIVideoItemRepository(client: APILibraryClient(api: client()))
        try await repository.replay(PendingAction(videoID: UUID(), queuedAt: .now, kind: .tags(["pasta"])))

        #expect(seen?.httpMethod == "PATCH")
        #expect(seen?.value(forHTTPHeaderField: "X-Queued-At") != nil)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["tags"] as? [String] == ["pasta"])
    }

    @Test func undoTellsTheBackendWhetherThePhoneWasShaken() async throws {
        var method: String?
        StubURLProtocol.handler = { request in
            method = request.value(forHTTPHeaderField: "X-Undo-Method")
            return (500, Data())
        }
        let repository = APIVideoItemRepository(client: APILibraryClient(api: client()))
        let video = LibraryFixtures.video()
        _ = try? await repository.restoreVideo(video, method: .shake)
        #expect(method == "shake")
        _ = try? await repository.restoreVideo(video)
        #expect(method == "button")
    }

    @Test func onlyRejectionsThatCanNeverSucceedAreDroppedFromTheOutbox() {
        func server(_ status: Int) -> APIClientError {
            .server(status: status, code: "x", detail: "x", email: nil, retryAfter: nil)
        }
        #expect(SyncManager.isPermanentFailure(server(404)))
        #expect(SyncManager.isPermanentFailure(server(410)))
        #expect(!SyncManager.isPermanentFailure(server(408)))
        #expect(!SyncManager.isPermanentFailure(server(429)))
        #expect(!SyncManager.isPermanentFailure(server(503)))
        #expect(!SyncManager.isPermanentFailure(APIClientError.networkUnavailable))
    }
}
