import SwiftUI

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
