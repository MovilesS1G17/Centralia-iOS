import Foundation

enum AnalyticsValue: Encodable, Sendable {
    case text(String)
    case integer(Int)
    case decimal(Double)
    case boolean(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        case let .decimal(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        }
    }
}

struct ClientAnalyticsEvent: Encodable, Sendable {
    let name: String
    let occurredAt: Date
    let properties: [String: AnalyticsValue]
}

protocol AnalyticsRepository {
    func record(_ events: [ClientAnalyticsEvent]) async throws
}
