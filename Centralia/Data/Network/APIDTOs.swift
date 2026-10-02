import Foundation

struct AuthSessionDTO: Decodable {
    let accessToken: String
    let tokenType: String
    let user: AuthenticatedUserDTO
}

struct AuthenticatedUserDTO: Decodable {
    let id: UUID
    let displayName: String
    let email: String?

    var model: AuthenticatedUser {
        AuthenticatedUser(id: id, displayName: displayName, email: email)
    }
}

struct VerificationPendingDTO: Decodable, Equatable {
    let status: String
    let email: String
    let resendAvailableIn: Int

    var model: VerificationPending {
        VerificationPending(email: email, resendAvailableIn: resendAvailableIn)
    }
}

struct PasswordResetAcceptedDTO: Decodable {
    let status: String
    let resendAvailableIn: Int
}

struct UserProfileDTO: Decodable {
    let id: UUID
    let displayName: String
    let email: String
    let membershipStatus: MembershipStatus

    var model: UserProfile {
        UserProfile(id: id, displayName: displayName, email: email, membershipStatus: membershipStatus)
    }

    var authenticatedUser: AuthenticatedUser {
        AuthenticatedUser(id: id, displayName: displayName, email: email)
    }
}

struct VideoDTO: Decodable {
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
    let thumbnailURL: URL?
    let embedURL: URL?

    var model: VideoItem {
        VideoItem(
            id: id, sourceURL: sourceURL, platform: platform, creator: creator,
            durationSeconds: durationSeconds, sourceCaption: sourceCaption,
            transcript: transcript, extractedOnScreenText: extractedOnScreenText,
            generatedSummary: generatedSummary, customTitle: customTitle,
            folderID: folderID, tags: tags, note: note, savedAt: savedAt,
            analysisStatus: analysisStatus
        )
    }
}

struct VideoPlaybackDTO: Decodable {
    let streamURL: String?
    let streamReady: Bool
    let expiresAt: Date?
    let embedURL: URL?

    func model(configuration: APIConfiguration) throws -> VideoPlayback {
        VideoPlayback(
            streamURL: try streamURL.map(configuration.streamURL(for:)),
            streamReady: streamReady,
            expiresAt: expiresAt,
            embedURL: embedURL
        )
    }
}

struct FolderDTO: Decodable {
    let id: UUID
    let name: String
    let symbolName: String

    var model: LibraryFolder {
        LibraryFolder(id: id, name: name, symbolName: symbolName)
    }
}

struct ImportedVideoMetadataDTO: Codable {
    let sourceURL: URL
    let platform: VideoPlatform
    let creator: String
    let durationSeconds: Int
    let sourceCaption: String?
    let transcript: String?
    let extractedOnScreenText: String?
    let generatedSummary: String?

    init(_ model: ImportedVideoMetadata) {
        sourceURL = model.sourceURL
        platform = model.platform
        creator = model.creator
        durationSeconds = model.durationSeconds
        sourceCaption = model.sourceCaption
        transcript = model.transcript
        extractedOnScreenText = model.extractedOnScreenText
        generatedSummary = model.generatedSummary
    }

    var model: ImportedVideoMetadata {
        ImportedVideoMetadata(
            sourceURL: sourceURL, platform: platform, creator: creator,
            durationSeconds: durationSeconds, sourceCaption: sourceCaption,
            transcript: transcript, extractedOnScreenText: extractedOnScreenText,
            generatedSummary: generatedSummary
        )
    }
}
