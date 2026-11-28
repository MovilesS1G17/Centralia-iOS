import Foundation
import Observation
import SwiftUI

@Observable
final class TrendsViewModel {
    private(set) var windowDays = 7
    private(set) var isLoading = false
    private(set) var result: TrendsResult?
    private(set) var errorMessage: String?

    private let repository: any TrendsLoading
    private let analytics: any AnalyticsTracking
    @ObservationIgnored private var requestID = 0

    init(repository: any TrendsLoading, analytics: any AnalyticsTracking = NoOpAnalyticsTracking()) {
        self.repository = repository
        self.analytics = analytics
    }

    func load(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        requestID += 1
        let currentRequest = requestID
        let days = windowDays
        let start = ContinuousClock.now
        defer {
            if currentRequest == requestID { isLoading = false }
        }
        do {
            let loaded = try await repository.load(windowDays: days, forceRefresh: forceRefresh)
            guard currentRequest == requestID, !Task.isCancelled else { return }
            result = loaded
            let elapsed = start.duration(to: .now).components
            let ms = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
            analytics.track(.trendsLoaded(
                source: loaded.source,
                durationMs: (ms * 10).rounded() / 10,
                stale: loaded.isStale,
                windowDays: days
            ))
        } catch is CancellationError {
            return
        } catch {
            guard currentRequest == requestID, !Task.isCancelled else { return }
            errorMessage = FeatureError.message(for: error)
        }
    }

    func select(windowDays days: Int) async {
        guard days != windowDays else { return }
        windowDays = days
        result = nil
        await load()
    }
}

struct TrendsView: View {
    @Environment(\.offlineLibraryStatus) private var offlineStatus
    @State private var viewModel: TrendsViewModel

    init(repository: any TrendsLoading, analytics: any AnalyticsTracking) {
        _viewModel = State(initialValue: TrendsViewModel(repository: repository, analytics: analytics))
    }

    private var isOnline: Bool { offlineStatus?.isOnline ?? true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
                Text("What people on Centralia are saving")
                    .font(.subheadline)
                    .foregroundStyle(Color.centraliaSecondaryText)

                HStack(spacing: CentraliaTheme.Spacing.small) {
                    windowChip("This week", days: 7)
                    windowChip("This month", days: 30)
                }

                if let result = viewModel.result {
                    Text(statusLine(result))
                        .font(.footnote)
                        .foregroundStyle(Color.centraliaSecondaryText)
                    content(result.trends)
                } else if let message = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Trends unavailable", systemImage: "icloud.slash")
                    } description: {
                        Text(isOnline && message == CachedTrendsRepository.offlineMessage
                             ? "Centralia couldn’t load Trends. Try again in a moment."
                             : message)
                    } actions: {
                        Button("Try Again") { Task { await viewModel.load(forceRefresh: true) } }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.centraliaInk)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ProgressView("Loading trends…")
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
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") { Task { await viewModel.load(forceRefresh: true) } }
                    .disabled(viewModel.isLoading)
            }
        }
        .task { if viewModel.result == nil && !viewModel.isLoading { await viewModel.load() } }
        .onChange(of: isOnline) { _, online in
            if online && (viewModel.result == nil || viewModel.result?.isStale == true) {
                Task { await viewModel.load() }
            }
        }
    }

    private func statusLine(_ result: TrendsResult) -> String {
        var line = CachedTrendsRepository.updatedLabel(result.fetchedAt)
        if result.source != .network { line += " · saved on this phone" }
        if !isOnline { line += " · you're offline" }
        else if result.isStale { line += " · couldn't refresh" }
        return line
    }

    private func windowChip(_ title: String, days: Int) -> some View {
        let selected = viewModel.windowDays == days
        return Button {
            Task { await viewModel.select(windowDays: days) }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.centraliaSurface : Color.centraliaInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(selected ? Color.centraliaInk : Color.centraliaSoftSurface, in: Capsule())
        }
        .buttonStyle(CentraliaPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func content(_ trends: Trends) -> some View {
        TrendsCard {
            Text("\(trends.totalSaves) shorts saved")
                .font(.title3.weight(.semibold))
            let total = max(trends.platformCounts.values.reduce(0, +), 1)
            ForEach(VideoPlatform.allCases) { platform in
                let count = trends.platformCounts[platform.rawValue] ?? 0
                TrendsBar(
                    label: platform.displayName,
                    value: "\(Int((100 * Double(count) / Double(total)).rounded()))%",
                    fraction: Double(count) / Double(total)
                )
            }
        }
        trendList("Top categories", trends.categories, empty: "Not enough people saved into the same folder yet.")
        trendList("Top tags", trends.tags, empty: "Not enough people used the same tag yet.")
        Text("Categories and tags appear when at least \(trends.minUsers) people use them.")
            .font(.footnote)
            .foregroundStyle(Color.centraliaSecondaryText)
    }

    private func trendList(_ title: String, _ items: [TrendItem], empty: String) -> some View {
        TrendsCard {
            Text(title).font(.headline)
            if items.isEmpty {
                Text(empty).font(.footnote).foregroundStyle(Color.centraliaSecondaryText)
            } else {
                let top = max(items.map(\.saves).max() ?? 1, 1)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        TrendsBar(label: item.name, value: "\(item.saves)", fraction: Double(item.saves) / Double(top))
                        Text("\(item.users) people")
                            .font(.caption)
                            .foregroundStyle(Color.centraliaSecondaryText)
                    }
                }
            }
        }
    }
}

private struct TrendsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CentraliaTheme.Spacing.medium)
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.centraliaDivider, lineWidth: 1))
    }
}

private struct TrendsBar: View {
    let label: String
    let value: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.subheadline)
                Spacer(minLength: CentraliaTheme.Spacing.small)
                Text(value).font(.footnote.weight(.semibold))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.centraliaSoftSurface)
                    Capsule().fill(Color.centraliaInk)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
