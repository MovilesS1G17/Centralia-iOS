import Foundation

private enum LibraryAPIError: LocalizedError {
    case sessionExpired, duplicate, unavailable, invalidResponse, message(String)
    var errorDescription: String? {
        switch self {
        case .sessionExpired: "Your session has expired. Please log in again."
        case .duplicate: "This short is already in your Centralia library."
        case .unavailable: "We couldn't reach Centralia. Check your connection and try again."
        case .invalidResponse: "Centralia returned an unexpected response."
        case .message(let value): value
        }
    }
}

struct APILibraryClient: @unchecked Sendable {
    let configuration: APIConfiguration
    let session: URLSession
    let tokenStore: any AuthenticationTokenStore

    init(configuration: APIConfiguration = .current, session: URLSession = .shared,
         tokenStore: any AuthenticationTokenStore = KeychainAuthenticationTokenStore()) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
    }

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let token = try tokenStore.accessToken() else { throw LibraryAPIError.sessionExpired }
        var request = URLRequest(url: configuration.endpoint(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LibraryAPIError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw LibraryAPIError.invalidResponse }
        if http.statusCode == 401 { throw LibraryAPIError.sessionExpired }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if http.statusCode == 409 {
                throw LibraryAPIError.message(detail?["detail"] as? String ?? LibraryAPIError.duplicate.localizedDescription)
            }
            throw LibraryAPIError.message(detail?["detail"] as? String ?? "Centralia couldn't complete this request.")
        }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                debugDescription: "Invalid saved_at timestamp")
        }
        do { return try decoder.decode(type, from: data) }
        catch { throw LibraryAPIError.invalidResponse }
    }

    func event(_ name: String, videoID: UUID, properties: [String: Any] = [:]) {
        Task.detached(priority: .utility) {
            for attempt in 0..<2 {
                do {
                    _ = try await request("/events", method: "POST", body: [
                        "event_name": name, "video_id": videoID.uuidString.lowercased(),
                        "client_platform": "ios", "properties": properties
                    ])
                    return
                } catch {
                    if attempt == 0 { try? await Task.sleep(for: .seconds(2)) }
                }
            }
        }
    }
}

private struct VideoWire: Decodable {
    let id: UUID
    let sourceURL: URL
    let platform: VideoPlatform
    let creator: String
    let durationSeconds: Int
    let sourceCaption: String?
    let transcript: String?
    let extractedOnScreenText: String?
    let generatedSummary: String?
    let customTitle: String?
    let folderID: UUID?
    let tags: [String]
    let note: String?
    let savedAt: Date
    let analysisStatus: ContentAnalysisStatus
    enum CodingKeys: String, CodingKey {
        case id, platform, creator, transcript, tags, note
        case sourceURL = "source_url", durationSeconds = "duration_seconds"
        case sourceCaption = "source_caption", extractedOnScreenText = "extracted_on_screen_text"
        case generatedSummary = "generated_summary", customTitle = "custom_title"
        case folderID = "folder_id", savedAt = "saved_at", analysisStatus = "analysis_status"
    }
    var item: VideoItem {
        VideoItem(id: id, sourceURL: sourceURL, platform: platform, creator: creator,
            durationSeconds: durationSeconds, sourceCaption: sourceCaption, transcript: transcript,
            extractedOnScreenText: extractedOnScreenText, generatedSummary: generatedSummary,
            customTitle: customTitle, folderID: folderID, tags: tags, note: note,
            savedAt: savedAt, analysisStatus: analysisStatus)
    }
}

private struct FolderWire: Decodable {
    let id: UUID
    let name: String
    let symbolName: String
    enum CodingKeys: String, CodingKey { case id, name; case symbolName = "symbol_name" }
    var folder: LibraryFolder { LibraryFolder(id: id, name: name, symbolName: symbolName) }
}

struct APIVideoItemRepository: VideoItemRepository {
    let client: APILibraryClient
    func videos() async throws -> [VideoItem] {
        try client.decode([VideoWire].self, data: await client.request("/videos")).map(\.item)
    }
    func saveVideo(_ video: VideoItem) async throws {
        let assignment = video.folderID == nil ? "none" : "manual"
        _ = try await client.request("/videos", method: "POST", body: [
            "id": video.id.uuidString.lowercased(), "source_url": video.sourceURL.absoluteString,
            "folder_id": video.folderID?.uuidString.lowercased() as Any? ?? NSNull(),
            "tags": video.tags, "note": video.note as Any? ?? NSNull(),
            "assignment_source": assignment
        ])
        client.event("video_saved", videoID: video.id, properties: [
            "platform": video.platform.rawValue, "tag_count": video.tags.count,
            "assignment_source": assignment
        ])
        client.event("organization_decision", videoID: video.id, properties: [
            "assignment_source": assignment
        ])
    }
    func deleteVideo(id: UUID) async throws {
        _ = try await client.request("/videos/\(id)", method: "DELETE")
    }
    func restoreVideo(_ video: VideoItem) async throws {
        _ = try await client.request("/videos/\(video.id)/restore", method: "POST")
    }
    func moveVideo(id: UUID, to folderID: UUID?) async throws {
        _ = try await client.request("/videos/\(id)/folder", method: "PATCH", body: [
            "folder_id": folderID?.uuidString.lowercased() as Any? ?? NSNull()
        ])
        client.event("organization_decision", videoID: id, properties: [
            "assignment_source": folderID == nil ? "none" : "manual"
        ])
    }
    func updateNote(id: UUID, note: String?) async throws {
        _ = try await client.request("/videos/\(id)/note", method: "PATCH", body: ["note": note as Any? ?? NSNull()])
    }
    func updateTags(id: UUID, tags: [String]) async throws {
        _ = try await client.request("/videos/\(id)/tags", method: "PATCH", body: ["tags": tags])
    }
    func recordSourceOpened(id: UUID) async {
        client.event("source_opened", videoID: id)
    }
}

struct APIFolderRepository: FolderRepository {
    let client: APILibraryClient
    func folders() async throws -> [LibraryFolder] {
        try client.decode([FolderWire].self, data: await client.request("/folders")).map(\.folder)
    }
    func createFolder(named name: String, symbolName: String) async throws -> LibraryFolder {
        try client.decode(FolderWire.self, data: await client.request("/folders", method: "POST", body: [
            "name": name, "symbol_name": symbolName
        ])).folder
    }
    func renameFolder(id: UUID, to name: String) async throws -> LibraryFolder {
        try client.decode(FolderWire.self, data: await client.request("/folders/\(id)", method: "PATCH", body: ["name": name])).folder
    }
    func deleteFolder(id: UUID) async throws {
        _ = try await client.request("/folders/\(id)", method: "DELETE")
    }
}

struct APIVideoImportPipeline: VideoImportPipeline {
    let client: APILibraryClient
    func detectPlatform(from sourceURL: URL) async throws -> VideoPlatform {
        guard sourceURL.scheme?.lowercased() == "https", let host = sourceURL.host?.lowercased() else {
            throw VideoImportError.invalidURL
        }
        let path = sourceURL.path.lowercased()
        if ["tiktok.com", "www.tiktok.com", "m.tiktok.com", "vm.tiktok.com"].contains(host),
           path.contains("/video/") || host == "vm.tiktok.com" { return .tiktok }
        if ["instagram.com", "www.instagram.com"].contains(host),
           path.contains("/reel/") || path.contains("/reels/") { return .instagramReel }
        if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host),
           path.contains("/shorts/") { return .youtubeShort }
        throw VideoImportError.unsupportedSource
    }
    func extractMetadata(from sourceURL: URL, platform: VideoPlatform) async throws -> ImportedVideoMetadata {
        let data = try await client.request("/videos/preview", method: "POST", body: ["source_url": sourceURL.absoluteString])
        let wire = try client.decode(PreviewWire.self, data: data)
        return ImportedVideoMetadata(sourceURL: wire.sourceURL, platform: wire.platform,
            creator: wire.creator, durationSeconds: wire.durationSeconds,
            sourceCaption: wire.sourceCaption, transcript: wire.transcript,
            extractedOnScreenText: wire.extractedOnScreenText, generatedSummary: wire.generatedSummary)
    }
    func generateTags(for metadata: ImportedVideoMetadata) async throws -> [String] { [] }
    func suggestFolder(for metadata: ImportedVideoMetadata, tags: [String]) async throws -> String? { nil }
}

private struct PreviewWire: Decodable {
    let sourceURL: URL
    let platform: VideoPlatform
    let creator: String
    let durationSeconds: Int
    let sourceCaption: String?
    let transcript: String?
    let extractedOnScreenText: String?
    let generatedSummary: String?
    enum CodingKeys: String, CodingKey {
        case platform, creator, transcript
        case sourceURL = "source_url", durationSeconds = "duration_seconds"
        case sourceCaption = "source_caption", extractedOnScreenText = "extracted_on_screen_text"
        case generatedSummary = "generated_summary"
    }
}
