import SwiftUI

/// Insights (Sprint 4, Gustavo · local storage). The last snapshot is read
/// from its JSON file and shown at once; the library is then read, the new
/// snapshot computed off the main actor and saved to the file again.
@Observable
final class InsightsViewModel {
    private(set) var snapshot: InsightsSnapshot?
    private(set) var sinceLastVisit: Int?
    private(set) var isUpdating = true
    private(set) var isFromLastVisit = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let videoRepository: any VideoItemRepository
    @ObservationIgnored private let services: Sprint4Services

    init(videoRepository: any VideoItemRepository, services: Sprint4Services) {
        self.videoRepository = videoRepository
        self.services = services
    }

    func load() async {
        let previous = await services.insights.load()
        if let previous {
            snapshot = previous
            isFromLastVisit = true
        }
        do {
            let facts = try await videoRepository.videos().map(VideoFacts.init)
            let now = Date()
            let current = await Task.detached(priority: .userInitiated) {
                Insights.compute(facts, now: now)
            }.value
            snapshot = current
            sinceLastVisit = Insights.sinceLastVisit(previous, current)
            isFromLastVisit = false
            isUpdating = false
            await services.insights.save(current)
            services.analytics.track(.insightsViewed(weeks: current.weeks.count))
        } catch {
            isUpdating = false
            errorMessage = FeatureError.message(for: error)
        }
    }
}

/// Sprint 4 view (Gustavo): the user's own saving habits.
struct InsightsView: View {
    @State private var viewModel: InsightsViewModel

    init(viewModel: InsightsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
                FeatureHeader(title: "Insights", subtitle: "How you save and organize, worked out on your phone.")
                if let snapshot = viewModel.snapshot {
                    if let note {
                        Text(note).font(.footnote).foregroundStyle(Color.centraliaSecondaryText)
                    }
                    content(snapshot)
                } else if let message = viewModel.errorMessage {
                    ContentUnavailableView("Insights unavailable", systemImage: "chart.bar", description: Text(message))
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ProgressView("Working out your insights…")
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .padding(.top, CentraliaTheme.Spacing.small)
            .padding(.bottom, CentraliaTheme.Spacing.xLarge)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color.centraliaCanvas.ignoresSafeArea())
        .foregroundStyle(Color.centraliaInk)
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
    }

    private var note: String? {
        if viewModel.isUpdating { return "Showing your last visit while we update…" }
        if viewModel.isFromLastVisit, let message = viewModel.errorMessage { return "From your last visit. \(message)" }
        return nil
    }

    @ViewBuilder
    private func content(_ snapshot: InsightsSnapshot) -> some View {
        FeatureCard {
            Text("This week").font(.headline).foregroundStyle(Color.centraliaSecondaryText)
            Text(snapshot.thisWeek == 1 ? "1 short saved" : "\(snapshot.thisWeek) shorts saved")
                .font(.title.weight(.semibold))
            Text(changeLine(snapshot))
                .font(.subheadline)
                .foregroundStyle(Color.centraliaSecondaryText)
            if let since = viewModel.sinceLastVisit, since > 0 {
                Text("Since your last visit: +\(since) saved").font(.subheadline.weight(.semibold))
            }
            if snapshot.streakWeeks >= 2 {
                Text("\(snapshot.streakWeeks)-week saving streak").font(.subheadline)
            }
        }

        FeatureCard {
            Text("Last \(snapshot.weeks.count) weeks").font(.headline)
            weekBars(snapshot)
        }

        FeatureCard {
            Text("Where you save from").font(.headline)
            let total = max(snapshot.totalSaves, 1)
            ForEach(["tiktok", "instagramReel", "youtubeShort"], id: \.self) { key in
                let count = snapshot.platformCounts[key] ?? 0
                LabeledBar(label: platformName(key), value: "\(count)", fraction: Double(count) / Double(total))
            }
        }

        FeatureCard {
            Text("Organized").font(.headline)
            LabeledBar(label: "In a folder", value: "\(snapshot.inFolderPct)%", fraction: Double(snapshot.inFolderPct) / 100)
            Text(snapshot.topTags.isEmpty ? "No tags yet." : "Your top tags: " + snapshot.topTags.joined(separator: ", "))
                .font(.footnote)
                .foregroundStyle(Color.centraliaSecondaryText)
        }
    }

    private func changeLine(_ snapshot: InsightsSnapshot) -> String {
        let change = snapshot.weekChange
        let first = change > 0 ? "\(change) more than last week" : change < 0 ? "\(-change) fewer than last week" : "Same as last week"
        return first + " · " + String(format: "%.1f", snapshot.averagePerWeek) + " a week on average"
    }

    private func weekBars(_ snapshot: InsightsSnapshot) -> some View {
        let top = max(snapshot.weeks.map(\.saves).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(snapshot.weeks.enumerated()), id: \.element.id) { index, week in
                VStack(spacing: 4) {
                    Text("\(week.saves)").font(.caption2).foregroundStyle(Color.centraliaSecondaryText)
                    UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6)
                        .fill(index == snapshot.weeks.count - 1 ? Color.centraliaInk : Color.centraliaVideoSand)
                        .frame(height: max(3, 96 * Double(week.saves) / Double(top)))
                    Text(Insights.shortLabel(week.weekStart))
                        .font(.caption2)
                        .foregroundStyle(Color.centraliaSecondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 150, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saves per week. " + snapshot.weeks.map { "\(Insights.shortLabel($0.weekStart)): \($0.saves)" }.joined(separator: "; "))
    }
}
