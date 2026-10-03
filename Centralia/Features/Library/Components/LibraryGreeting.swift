import SwiftUI

/// A context-aware Library greeting driven by the phone's local time zone.
struct LibraryGreeting: View {
    let displayName: String?

    var body: some View {
        TimelineView(.everyMinute) { context in
            let greeting = TimeOfDayGreeting.greeting(
                at: context.date,
                displayName: displayName
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(greeting.title)
                    .font(CentraliaTheme.Typography.sectionTitle)
                    .foregroundStyle(Color.centraliaInk)
                    .accessibilityAddTraits(.isHeader)

                Text(greeting.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.centraliaSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
