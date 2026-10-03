import Foundation

/// The context-aware greeting at the top of the Library.
///
/// It follows the phone's clock in the phone's time zone and refreshes in the
/// client, so it adapts as the user moves through the day or travels.
enum TimeOfDayGreeting {
    enum PartOfDay: Equatable {
        case morning, afternoon, evening, night
    }

    struct Greeting: Equatable {
        let title: String
        let subtitle: String
        let partOfDay: PartOfDay
    }

    static func partOfDay(hour: Int) -> PartOfDay {
        switch hour {
        case 5...11: return .morning
        case 12...17: return .afternoon
        case 18...21: return .evening
        default: return .night
        }
    }

    /// "David Caro" becomes "David"; blank names give no name at all.
    static func firstName(_ displayName: String?) -> String? {
        guard let first = displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .first
        else { return nil }
        return String(first)
    }

    static func greeting(
        at date: Date = Date(),
        displayName: String? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Greeting {
        let part = partOfDay(hour: calendar.component(.hour, from: date))

        let salutation: String
        switch part {
        case .morning: salutation = "Good morning"
        case .afternoon: salutation = "Good afternoon"
        case .evening, .night: salutation = "Good evening"
        }

        let subtitle: String
        switch part {
        case .morning: subtitle = "Start your day with something you saved."
        case .afternoon: subtitle = "A good moment to catch up on your shorts."
        case .evening: subtitle = "Wind down with something from your library."
        case .night: subtitle = "Up late? Your shorts are waiting."
        }

        let title = firstName(displayName).map { "\(salutation), \($0)" } ?? salutation
        return Greeting(title: title, subtitle: subtitle, partOfDay: part)
    }
}
