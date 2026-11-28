import SwiftUI

/// Rediscover (Sprint 4, Enrique's feature on iOS · multithreading).
///
/// `load()` runs on the main actor and spreads the work:
///  1. `async let`: the library, the "Recently viewed" history (Core Data,
///     background context) and the "Not now" list are read at the same time.
///  2. `Task.detached` + `Rediscover.pickInParallel`: scoring runs off the main
///     actor, one child task per chunk in a task group.
///  3. Back on the main actor, the picks are matched to the shorts and shown.
struct RediscoverItem: Identifiable {
    let pick: RediscoverPick
    let video: VideoItem
    var id: UUID { pick.videoID }
}

@Observable
final class RediscoverViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var state: LoadState = .idle
    private(set) var items: [RediscoverItem] = []
    private(set) var librarySize = 0

    @ObservationIgnored private let videoRepository: any VideoItemRepository
    @ObservationIgnored private let recentlyViewed: RecentlyViewedHistory?
    @ObservationIgnored private let dismissals: any RediscoverDismissing

    init(videoRepository: any VideoItemRepository, recentlyViewed: RecentlyViewedHistory?, dismissals: any RediscoverDismissing) {
        self.videoRepository = videoRepository
        self.recentlyViewed = recentlyViewed
        self.dismissals = dismissals
    }

    func load() async {
        if items.isEmpty { state = .loading }
        let now = Date()
        do {
            let store = recentlyViewed
            async let library = videoRepository.videos()
            async let history: [RecentlyViewedEntry] = store?.recent(limit: RecentlyViewed.maxStored) ?? []
            let dismissed = dismissals.active(now: now)
            let videos = try await library
            let lastViewed = Dictionary(
                (await history).map { ($0.videoID, $0.lastViewedAt) },
                uniquingKeysWith: { first, _ in first }
            )
            let facts = videos.map(VideoFacts.init)
            let picks = await Task.detached(priority: .userInitiated) {
                await Rediscover.pickInParallel(facts, lastViewed: lastViewed, dismissed: dismissed, now: now)
            }.value
            guard !Task.isCancelled else { return }
            let byID = Dictionary(videos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            items = picks.compactMap { pick in byID[pick.videoID].map { RediscoverItem(pick: pick, video: $0) } }
            librarySize = videos.count
            state = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(FeatureError.message(for: error))
        }
    }

    /// "Not now": hidden for 30 days; the list closes the gap right away.
    func notNow(_ pick: RediscoverPick) {
        items.removeAll { $0.pick.videoID == pick.videoID }
        dismissals.dismiss(pick.videoID, at: Date())
    }
}

/// Sprint 4 view (Enrique): shorts saved a while ago and not opened since.
struct RediscoverView: View {
    @State private var viewModel: RediscoverViewModel
    private let isOnline: Bool
    private let openVideo: (VideoItem) -> Void

    init(viewModel: RediscoverViewModel, isOnline: Bool, openVideo: @escaping (VideoItem) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.isOnline = isOnline
        self.openVideo = openVideo
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                FeatureHeader(
                    title: "Rediscover",
                    subtitle: "Shorts you saved a while ago and haven't opened since. A new pick every day."
                )
                if !isOnline {
                    Text("You're offline. These picks come from the copy of your library on this phone.")
                        .font(.footnote)
                        .foregroundStyle(Color.centraliaSecondaryText)
                }
                content
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Looking for forgotten shorts…")
                .frame(maxWidth: .infinity, minHeight: 360)
        case let .failed(message):
            ContentUnavailableView {
                Label("Rediscover unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.centraliaInk)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        case .loaded:
            if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "Nothing to rediscover yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(viewModel.librarySize == 0
                        ? "Save a few shorts first. In a week, the ones you haven't opened will show up here."
                        : "No saved shorts match your picks right now. Check back later.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                ForEach(viewModel.items) { item in
                    ShortRow(video: item.video, detail: item.pick.reason) {
                        openVideo(item.video)
                    } trailing: {
                        Button("Not now") { viewModel.notNow(item.pick) }
                            .buttonStyle(.bordered)
                    }
                }
                Text("\"Not now\" hides a short from Rediscover for 30 days.")
                    .font(.caption)
                    .foregroundStyle(Color.centraliaSecondaryText)
            }
        }
    }
}
