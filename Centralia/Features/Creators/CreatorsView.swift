import SwiftUI

/// Creators (Sprint 4, Alejandro). The library is read, copied into
/// `VideoFacts` and grouped per platform in parallel off the main actor
/// (`Creators.groupInParallel`), unless the LRU cache already has this library.
@Observable
final class CreatorsViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var state: LoadState = .idle
    private(set) var creators: [CreatorSummary] = []
    var expanded: String?
    var query = ""

    @ObservationIgnored private var videosByID: [UUID: VideoItem] = [:]
    @ObservationIgnored private let videoRepository: any VideoItemRepository
    @ObservationIgnored private let cache: CreatorsCache
    @ObservationIgnored private let analytics: any AnalyticsTracking
    @ObservationIgnored private var hasTrackedView = false

    init(videoRepository: any VideoItemRepository, cache: CreatorsCache, analytics: any AnalyticsTracking = NoOpAnalyticsTracking()) {
        self.videoRepository = videoRepository
        self.cache = cache
        self.analytics = analytics
    }

    var visible: [CreatorSummary] {
        let wanted = Creators.key(query)
        guard !wanted.isEmpty else { return creators }
        return creators.filter { $0.id.contains(wanted) }
    }

    func videos(of creator: CreatorSummary) -> [VideoItem] {
        creator.videoIDs.compactMap { videosByID[$0] }
    }

    func load() async {
        if creators.isEmpty { state = .loading }
        do {
            let videos = try await videoRepository.videos()
            let facts = videos.map(VideoFacts.init)
            let cache = self.cache
            let grouped = await Task.detached(priority: .userInitiated) {
                let key = Creators.fingerprint(facts)
                if let cached = cache.value(for: key) { return cached }
                let grouped = await Creators.groupInParallel(facts)
                cache.insert(grouped, for: key)
                return grouped
            }.value
            guard !Task.isCancelled else { return }
            videosByID = Dictionary(videos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            creators = grouped
            state = .loaded
            if !hasTrackedView {
                hasTrackedView = true
                analytics.track(.creatorsViewed(creators: grouped.count))
            }
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(FeatureError.message(for: error))
        }
    }

    func toggle(_ creator: CreatorSummary) {
        expanded = expanded == creator.id ? nil : creator.id
    }
}

/// Sprint 4 view (Alejandro): saved shorts grouped by creator.
struct CreatorsView: View {
    @State private var viewModel: CreatorsViewModel
    private let openVideo: (VideoItem) -> Void

    init(viewModel: CreatorsViewModel, openVideo: @escaping (VideoItem) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.openVideo = openVideo
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                FeatureHeader(title: "Creators", subtitle: "Everyone you've saved shorts from, most saved first.")
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
            ProgressView("Grouping your shorts by creator…")
                .frame(maxWidth: .infinity, minHeight: 360)
        case let .failed(message):
            ContentUnavailableView {
                Label("Creators unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.centraliaInk)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        case .loaded:
            if viewModel.creators.isEmpty {
                ContentUnavailableView(
                    "No creators yet",
                    systemImage: "person.2",
                    description: Text("Save a short and its creator will show up here.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                TextField("Search creators", text: $viewModel.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, CentraliaTheme.Spacing.medium)
                    .frame(minHeight: 52)
                    .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.centraliaDivider, lineWidth: 1))
                ForEach(viewModel.visible) { creator in
                    creatorCard(creator)
                }
            }
        }
    }

    private func creatorCard(_ creator: CreatorSummary) -> some View {
        let isExpanded = viewModel.expanded == creator.id
        return VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { viewModel.toggle(creator) }
            } label: {
                HStack(spacing: 12) {
                    Text(creator.initial)
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(Color.centraliaSoftSurface, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(creator.handle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(
                            "\(creator.count == 1 ? "1 short" : "\(creator.count) shorts") · "
                                + creator.platformsRaw.map(platformName).joined(separator: " · ")
                                + " · " + savedAgoLabel(creator.lastSavedAt)
                        )
                        .font(.caption)
                        .foregroundStyle(Color.centraliaSecondaryText)
                        .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(Color.centraliaSecondaryText)
                }
                .padding(12)
                .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.centraliaDivider, lineWidth: 1))
            }
            .buttonStyle(CentraliaPressStyle())
            .foregroundStyle(Color.centraliaInk)
            .accessibilityHint(isExpanded ? "Hides this creator's shorts" : "Shows this creator's shorts")

            if isExpanded {
                ForEach(viewModel.videos(of: creator)) { video in
                    ShortRow(video: video, detail: savedAgoLabel(video.savedAt)) { openVideo(video) }
                }
            }
        }
    }
}
