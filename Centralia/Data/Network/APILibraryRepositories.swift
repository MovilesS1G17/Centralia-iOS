import Foundation

struct APILibraryClient {
    let api: APIClient

    init(
        configuration: APIConfiguration = .current,
        session: URLSession = .shared,
        tokenStore: any AuthenticationTokenStore = KeychainAuthenticationTokenStore()
    ) {
        api = APIClient(configuration: configuration, session: session, tokenStore: tokenStore)
    }

    init(api: APIClient) {
        self.api = api
    }

    func request<Response: Decodable>(
        _ type: Response.Type, path: String, method: String = "GET", body: Data? = nil
    ) async throws -> Response {
        try await api.request(type, path: path, method: method, body: body)
    }

    func send(_ path: String, method: String, body: Data? = nil) async throws {
        _ = try await api.send(path, method: method, body: body)
    }

    func encode<Body: Encodable>(_ body: Body) throws -> Data {
        try api.encode(body)
    }

    func patch(_ path: String, values: [String: Any]) async throws {
        try await send(path, method: "PATCH", body: JSONSerialization.data(withJSONObject: values))
    }
}

private struct VideoCreateBody: Encodable {
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
    let analysisStatus: ContentAnalysisStatus

    init(_ video: VideoItem) {
        id = video.id
        sourceURL = video.sourceURL
        platform = video.platform
        creator = video.creator
        durationSeconds = video.durationSeconds
        sourceCaption = video.sourceCaption
        transcript = video.transcript
        extractedOnScreenText = video.extractedOnScreenText
        generatedSummary = video.generatedSummary
        customTitle = video.customTitle
        folderID = video.folderID
        tags = video.tags
        note = video.note
        analysisStatus = video.analysisStatus
    }
}

private struct FolderCreateBody: Encodable {
    let name: String
    let symbolName: String
}

private struct FolderRenameBody: Encodable {
    let name: String
}

private struct DetectBody: Encodable {
    let sourceURL: URL
}

private struct DetectResponse: Decodable {
    let platform: VideoPlatform
}

private struct MetadataBody: Encodable {
    let sourceURL: URL
    let platform: VideoPlatform
}

private struct TagsBody: Encodable {
    let metadata: ImportedVideoMetadataDTO
}

private struct TagsResponse: Decodable {
    let tags: [String]
}

private struct SuggestionBody: Encodable {
    let metadata: ImportedVideoMetadataDTO
    let tags: [String]
}

private struct SuggestionResponse: Decodable {
    let folderName: String?
}

struct APIVideoItemRepository: VideoItemRepository {
    let client: APILibraryClient

    func videos() async throws -> [VideoItem] {
        try await client.request([VideoDTO].self, path: "/v1/videos").map(\.model)
    }

    func saveVideo(_ video: VideoItem) async throws {
        let body = try client.encode(VideoCreateBody(video))
        _ = try await client.request(VideoDTO.self, path: "/v1/videos", method: "POST", body: body)
    }

    func deleteVideo(id: UUID) async throws {
        try await client.send("/v1/videos/\(id)", method: "DELETE")
    }

    func restoreVideo(_ video: VideoItem) async throws {
        _ = try await client.request(VideoDTO.self, path: "/v1/videos/\(video.id)/restore", method: "POST")
    }

    func moveVideo(id: UUID, to folderID: UUID?) async throws {
        try await client.patch("/v1/videos/\(id)", values: ["folderID": folderID?.uuidString.lowercased() ?? NSNull() as Any])
    }

    func updateNote(id: UUID, note: String?) async throws {
        try await client.patch("/v1/videos/\(id)", values: ["note": note ?? NSNull() as Any])
    }

    func updateTags(id: UUID, tags: [String]) async throws {
        try await client.patch("/v1/videos/\(id)", values: ["tags": tags])
    }

    func recordSourceOpened(id: UUID) async {
        _ = try? await client.request(VideoDTO.self, path: "/v1/videos/\(id)")
    }
}

struct APIVideoPlaybackRepository: VideoPlaybackRepository {
    let client: APILibraryClient

    func playback(for videoID: UUID) async throws -> VideoPlayback {
        let dto = try await client.request(
            VideoPlaybackDTO.self, path: "/v1/videos/\(videoID)/playback"
        )
        return try dto.model(configuration: client.api.configuration)
    }
}

struct APIFolderRepository: FolderRepository {
    let client: APILibraryClient

    func folders() async throws -> [LibraryFolder] {
        try await client.request([FolderDTO].self, path: "/v1/folders").map(\.model)
    }

    func createFolder(named name: String, symbolName: String) async throws -> LibraryFolder {
        let body = try client.encode(FolderCreateBody(name: name, symbolName: symbolName))
        return try await client.request(FolderDTO.self, path: "/v1/folders", method: "POST", body: body).model
    }

    func renameFolder(id: UUID, to name: String) async throws -> LibraryFolder {
        let body = try client.encode(FolderRenameBody(name: name))
        return try await client.request(FolderDTO.self, path: "/v1/folders/\(id)", method: "PATCH", body: body).model
    }

    func deleteFolder(id: UUID) async throws {
        try await client.send("/v1/folders/\(id)", method: "DELETE")
    }
}

struct APIVideoImportPipeline: VideoImportPipeline {
    let client: APILibraryClient

    func detectPlatform(from sourceURL: URL) async throws -> VideoPlatform {
        let body = try client.encode(DetectBody(sourceURL: sourceURL))
        return try await client.request(
            DetectResponse.self, path: "/v1/imports/detect", method: "POST", body: body
        ).platform
    }

    func extractMetadata(from sourceURL: URL, platform: VideoPlatform) async throws -> ImportedVideoMetadata {
        let body = try client.encode(MetadataBody(sourceURL: sourceURL, platform: platform))
        return try await client.request(
            ImportedVideoMetadataDTO.self, path: "/v1/imports/metadata", method: "POST", body: body
        ).model
    }

    func generateTags(for metadata: ImportedVideoMetadata) async throws -> [String] {
        let body = try client.encode(TagsBody(metadata: ImportedVideoMetadataDTO(metadata)))
        return try await client.request(
            TagsResponse.self, path: "/v1/imports/tags", method: "POST", body: body
        ).tags
    }

    func suggestFolder(for metadata: ImportedVideoMetadata, tags: [String]) async throws -> String? {
        let body = try client.encode(SuggestionBody(metadata: ImportedVideoMetadataDTO(metadata), tags: tags))
        return try await client.request(
            SuggestionResponse.self, path: "/v1/imports/folder-suggestion", method: "POST", body: body
        ).folderName
    }
}
