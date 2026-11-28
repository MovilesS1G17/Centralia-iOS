import SwiftUI

/// The five Sprint 4 views, reachable from the "Discover" row on the Library.
enum DiscoverDestination: String, CaseIterable, Identifiable, Hashable {
    case trends, creators, rediscover, insights
    case watchLater = "watch_later"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watchLater: "Watch later"
        case .rediscover: "Rediscover"
        case .creators: "Creators"
        case .trends: "Trends"
        case .insights: "Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .watchLater: "bookmark"
        case .rediscover: "clock.arrow.circlepath"
        case .creators: "person.2"
        case .trends: "flame"
        case .insights: "chart.bar"
        }
    }
}

/// A row of capsules on the Library, one per Sprint 4 view.
struct DiscoverShortcutsRow: View {
    let open: (DiscoverDestination) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                ForEach(DiscoverDestination.allCases) { destination in
                    Button {
                        open(destination)
                    } label: {
                        Label(destination.title, systemImage: destination.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.centraliaInk)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(Color.centraliaSurface, in: Capsule())
                            .overlay(Capsule().stroke(Color.centraliaDivider, lineWidth: 1))
                    }
                    .buttonStyle(CentraliaPressStyle())
                    .accessibilityHint("Opens \(destination.title)")
                    .accessibilityIdentifier("discover_\(destination.rawValue)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Back button, large title and a one-line description: the top of every Sprint 4 view.
struct FeatureHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    init(title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.xSmall) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(CentraliaPressStyle())
                .accessibilityLabel("Back")

                Text(title)
                    .font(CentraliaTheme.Typography.display)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)
                trailing()
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.centraliaSecondaryText)
        }
        .foregroundStyle(Color.centraliaInk)
    }
}

/// A short as a list row: small cover, title, a detail line and trailing actions.
struct ShortRow<Trailing: View>: View {
    let video: VideoItem
    let detail: String
    let open: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(video: VideoItem, detail: String, open: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.video = video
        self.detail = detail
        self.open = open
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ZStack {
                        Color.centraliaSoftSurface
                        VideoCoverImage(url: video.coverURL)
                    }
                    .frame(width: 56, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.centraliaInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(video.creatorDisplayName) · \(video.platform.displayName)")
                            .font(.caption)
                            .foregroundStyle(Color.centraliaSecondaryText)
                            .lineLimit(1)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Color.centraliaSecondaryText)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(CentraliaPressStyle())
            .accessibilityHint("Opens the short")

            trailing()
        }
        .padding(10)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.centraliaDivider, lineWidth: 1))
    }
}

extension FeatureHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension ShortRow where Trailing == EmptyView {
    init(video: VideoItem, detail: String, open: @escaping () -> Void) {
        self.init(video: video, detail: detail, open: open) { EmptyView() }
    }
}

/// "Platform" display name from its raw value.
func platformName(_ raw: String) -> String {
    VideoPlatform(rawValue: raw)?.displayName ?? raw
}

/// "saved today" / "saved yesterday" / "saved 5 days ago".
func savedAgoLabel(_ date: Date, now: Date = .now, verb: String = "saved") -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    switch days {
    case ...0: return "\(verb) today"
    case 1: return "\(verb) yesterday"
    default: return "\(verb) \(days) days ago"
    }
}

/// A white rounded card for a block of content (Trends, Insights).
struct FeatureCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CentraliaTheme.Spacing.medium)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.centraliaDivider, lineWidth: 1))
    }
}

/// A labelled horizontal bar: label, bar proportional to `fraction`, value.
struct LabeledBar: View {
    let label: String
    let value: String
    let fraction: Double

    var body: some View {
        HStack(spacing: CentraliaTheme.Spacing.small) {
            Text(label)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.centraliaSoftSurface)
                    Capsule().fill(Color.centraliaInk)
                        .frame(width: proxy.size.width * min(max(fraction, 0.02), 1))
                }
            }
            .frame(height: 10)
            Text(value)
                .font(.footnote.weight(.semibold))
                .frame(minWidth: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small text action used on the rows ("Not now", "Remove").
struct RowTextAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.centraliaInk)
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(CentraliaPressStyle())
    }
}
