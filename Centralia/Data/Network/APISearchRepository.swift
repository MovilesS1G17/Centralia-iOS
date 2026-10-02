import Foundation

/// The device-model identifier the backend expects in `X-Device-Model`
/// (e.g. "iPhone15,2") — the raw `utsname` machine identifier, not
/// `UIDevice.model` (which only ever returns the generic "iPhone").
func currentDeviceModelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce(into: "") { identifier, element in
        guard let value = element.value as? Int8, value != 0 else { return }
        identifier += String(UnicodeScalar(UInt8(value)))
    }
    return identifier.isEmpty ? "unknown" : identifier
}

struct APISearchRepository: SearchRepository {
    let client: APILibraryClient

    func search(
        query: String?,
        platform: VideoPlatform?,
        creator: String?,
        folderID: UUID?,
        tag: String?,
        limit: Int?,
        offset: Int
    ) async throws -> SearchResult {
        var queryItems: [URLQueryItem] = []
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        if let platform {
            queryItems.append(URLQueryItem(name: "platform", value: platform.rawValue))
        }
        if let creator, !creator.isEmpty {
            queryItems.append(URLQueryItem(name: "creator", value: creator))
        }
        if let folderID {
            queryItems.append(URLQueryItem(name: "folder_id", value: folderID.uuidString.lowercased()))
        }
        if let tag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if offset > 0 {
            queryItems.append(URLQueryItem(name: "offset", value: String(offset)))
        }

        let headers = [
            "X-Device-Model": currentDeviceModelIdentifier(),
            "X-Client-Platform": "ios",
        ]
        let (data, response) = try await client.requestWithResponse(
            "/videos", queryItems: queryItems, headers: headers
        )
        let videos = try client.decode([VideoWire].self, data: data).map(\.item)
        let totalCount = response.value(forHTTPHeaderField: "X-Total-Count").flatMap(Int.init) ?? videos.count
        return SearchResult(videos: videos, totalCount: totalCount)
    }

    func reportSearchCompleted(durationMs: Int, resultCount: Int, filterCount: Int) {
        client.searchCompletedEvent(
            durationMs: durationMs,
            resultCount: resultCount,
            deviceModel: currentDeviceModelIdentifier(),
            filterCount: filterCount
        )
    }
}
