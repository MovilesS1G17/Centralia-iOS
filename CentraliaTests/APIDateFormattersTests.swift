import Foundation
import Testing
@testable import Centralia

struct APIDateFormattersTests {
    @Test func parsesTimestampsWithAndWithoutFractionalSeconds() throws {
        let whole = try #require(APIDateFormatters.parse("2026-11-26T15:00:00Z"))
        let fraction = try #require(APIDateFormatters.parse("2026-11-26T15:00:00.250Z"))
        #expect(fraction.timeIntervalSince(whole) == 0.25)
        #expect(APIDateFormatters.parse("not a timestamp") == nil)
    }

    @Test func queuedTimestampRetainsMilliseconds() throws {
        let date = try #require(APIDateFormatters.parse("2026-11-26T15:00:00.250Z"))
        #expect(PendingAction.timestamp(date) == "2026-11-26T15:00:00.250Z")
    }
}
