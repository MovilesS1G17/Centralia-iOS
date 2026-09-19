import Foundation

enum MembershipStatus: String, Codable, Sendable {
    case centraliaMember

    var displayName: String {
        switch self {
        case .centraliaMember:
            "Centralia member"
        }
    }
}

struct UserProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var email: String
    let membershipStatus: MembershipStatus

    var initials: String {
        let letters = displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
        let value = String(letters).uppercased()
        return value.isEmpty ? "C" : value
    }

    var authenticatedUser: AuthenticatedUser {
        AuthenticatedUser(id: id, displayName: displayName, email: email)
    }
}

struct NotificationPreferences: Codable, Equatable, Sendable {
    var organizationReminders: Bool
    var weeklyLibrarySummary: Bool
    var productUpdates: Bool

    static let defaults = NotificationPreferences(
        organizationReminders: true,
        weeklyLibrarySummary: true,
        productUpdates: false
    )
}

struct LibraryStatistics: Equatable, Sendable {
    let savedCount: Int
    let folderCount: Int
    let unorganizedCount: Int
    let platformCounts: [VideoPlatform: Int]

    static let empty = LibraryStatistics(
        savedCount: 0,
        folderCount: 0,
        unorganizedCount: 0,
        platformCounts: [:]
    )

    func count(for platform: VideoPlatform) -> Int {
        platformCounts[platform, default: 0]
    }
}

struct ProfileStorageUsage: Equatable, Sendable {
    let usedGigabytes: Double
    let capacityGigabytes: Double

    var fractionUsed: Double {
        guard capacityGigabytes > 0 else { return 0 }
        return min(max(usedGigabytes / capacityGigabytes, 0), 1)
    }

    var percentage: Int {
        Int((fractionUsed * 100).rounded())
    }

    var summary: String {
        "\(usedGigabytes.formatted(.number.precision(.fractionLength(1)))) GB of \(capacityGigabytes.formatted(.number.precision(.fractionLength(0)))) GB (\(percentage)%)"
    }

    static let mock = ProfileStorageUsage(usedGigabytes: 2.4, capacityGigabytes: 5)
}
