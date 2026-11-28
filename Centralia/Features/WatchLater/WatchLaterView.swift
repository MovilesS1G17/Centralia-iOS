import SwiftUI

/// Watch later (Sprint 4, Alex's feature on iOS · local storage in Core Data).
@Observable
final class WatchLaterViewModel {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var state: LoadState = .idle
    private(set) var items: [WatchLaterItem] = []

    var unwatched: [WatchLaterItem] { items.filter { !$0.entry.isWatched } }
    var watched: [WatchLaterItem] { items.filter(\.entry.isWatched) }

    @ObservationIgnored private let videoRepository: any VideoItemRepository
    @ObservationIgnored private let store: any WatchLaterStoring
    @ObservationIgnored private var library: [VideoItem]?

    init(videoRepository: any VideoItemRepository, store: any WatchLaterStoring) {
        self.videoRepository = videoRepository
        self.store = store
    }

    func load() async {
        if library == nil { state = .loading }
        do {
            library = try await videoRepository.videos()
            await reload()
            state = .loaded
        } catch {
            state = .failed(FeatureError.message(for: error))
        }
    }

    /// Reads the queue again (Core Data, background context) after every change.
    private func reload() async {
        let entries = await store.entries()
        items = WatchLaterItem.visible(entries, in: library ?? [])
    }

    /// Opening from the queue marks it watched (BQ12: watched within 7 days?).
    func open(_ video: VideoItem) async {
        _ = await store.markWatched(video.id, at: .now)
        await reload()
    }

    func move(_ video: VideoItem, by offset: Int) async {
        await store.move(video.id, by: offset)
        await reload()
    }

    func remove(_ video: VideoItem) async {
        await store.remove(video.id)
        await reload()
    }

    func clearWatched() async {
        await store.clearWatched()
        await reload()
    }
}

/// Sprint 4 view (Alex): the Watch later queue.
struct WatchLaterView: View {
    @State private var viewModel: WatchLaterViewModel
    private let openVideo: (VideoItem) -> Void

    init(viewModel: WatchLaterViewModel, openVideo: @escaping (VideoItem) -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.openVideo = openVideo
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                FeatureHeader(title: "Watch later", subtitle: "Your queue lives on this phone, so it works offline too.")
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
            ProgressView("Loading your queue…")
                .frame(maxWidth: .infinity, minHeight: 360)
        case let .failed(message):
            ContentUnavailableView {
                Label("Watch later unavailable", systemImage: "exclamationmark.triangle")
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
                    "Your queue is empty",
                    systemImage: "bookmark",
                    description: Text("Open a short and tap \"Watch later\" to line it up here.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                let unwatched = viewModel.unwatched
                Text(unwatched.count == 1 ? "1 short to watch" : "\(unwatched.count) shorts to watch")
                    .font(.headline)
                    .foregroundStyle(Color.centraliaSecondaryText)
                ForEach(Array(unwatched.enumerated()), id: \.element.id) { index, item in
                    ShortRow(video: item.video, detail: "#\(index + 1) · \(savedAgoLabel(item.entry.addedAt, verb: "Added"))") {
                        Task { await viewModel.open(item.video) }
                        openVideo(item.video)
                    } trailing: {
                        VStack(spacing: 0) {
                            arrow("chevron.up", label: "Move up", enabled: index > 0) {
                                Task { await viewModel.move(item.video, by: -1) }
                            }
                            arrow("chevron.down", label: "Move down", enabled: index < unwatched.count - 1) {
                                Task { await viewModel.move(item.video, by: 1) }
                            }
                        }
                        RowTextAction(title: "Remove") { Task { await viewModel.remove(item.video) } }
                    }
                }
                let watched = viewModel.watched
                if !watched.isEmpty {
                    HStack {
                        Text("Watched")
                            .font(CentraliaTheme.Typography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        RowTextAction(title: "Clear watched") { Task { await viewModel.clearWatched() } }
                    }
                    .padding(.top, CentraliaTheme.Spacing.small)
                    ForEach(watched) { item in
                        ShortRow(video: item.video, detail: "Watched · \(savedAgoLabel(item.entry.addedAt, verb: "Added"))") {
                            openVideo(item.video)
                        } trailing: {
                            RowTextAction(title: "Remove") { Task { await viewModel.remove(item.video) } }
                        }
                    }
                }
            }
        }
    }

    private func arrow(_ systemImage: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(CentraliaPressStyle())
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.centraliaInk : Color.centraliaDivider)
        .accessibilityLabel(label)
    }
}

/// The "Watch later" button on the detail screen: reads and writes the Core Data queue.
struct WatchLaterToggle: View {
    let video: VideoItem
    let store: any WatchLaterStoring
    @State private var isQueued: Bool?
    @State private var isUpdating = false

    var body: some View {
        Group {
            if let isQueued {
                Button {
                    Task { await toggle(isQueued) }
                } label: {
                    Label(isQueued ? "In Watch later" : "Watch later", systemImage: isQueued ? "bookmark.fill" : "bookmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(isQueued ? Color.centraliaSurface : Color.centraliaInk)
                        .background(isQueued ? Color.centraliaInk : Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.centraliaDivider, lineWidth: 1))
                }
                .buttonStyle(CentraliaPressStyle())
                .disabled(isUpdating)
                .accessibilityHint(isQueued ? "Removes it from Watch later" : "Adds it to Watch later")
                .accessibilityIdentifier("watchLaterToggle")
            }
        }
        .task(id: video.id) { isQueued = await store.contains(video.id) }
    }

    private func toggle(_ queued: Bool) async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        if queued {
            await store.remove(video.id)
        } else {
            _ = await store.add(videoID: video.id, title: video.displayTitle, creator: video.creator, at: .now)
        }
        isQueued = await store.contains(video.id)
    }
}
