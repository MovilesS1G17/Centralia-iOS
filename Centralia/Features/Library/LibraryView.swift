import SwiftUI

struct LibraryView: View {
    @Environment(\.offlineLibraryStatus) private var offlineStatus
    @Environment(\.recentlyViewed) private var recentlyViewed
    private enum Route: Hashable {
        case discover(DiscoverDestination)
        case video(VideoDetailRoute)
        case folder(LibraryFolder)
    }

    @State private var viewModel: LibraryViewModel
    @Binding private var selectedTab: AppTab
    @State private var path: [Route] = []
    @State private var pendingDeletion: VideoItem?
    @State private var movingVideo: VideoItem?
    @State private var recentEntries: [RecentlyViewedEntry] = []

    private let presentSave: () -> Void
    private let userDisplayName: String?
    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let analytics: any AnalyticsTracking
    private let playbackRepository: (any VideoPlaybackRepository)?
    private let sprint4: Sprint4Services

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        selectedTab: Binding<AppTab>,
        userDisplayName: String? = nil,
        playbackRepository: (any VideoPlaybackRepository)? = nil,
        analytics: any AnalyticsTracking = NoOpAnalyticsTracking(),
        sprint4: Sprint4Services,
        presentSave: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: LibraryViewModel(
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                analytics: analytics
            )
        )
        self.analytics = analytics
        self.playbackRepository = playbackRepository
        self.sprint4 = sprint4
        _selectedTab = selectedTab
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.presentSave = presentSave
        self.userDisplayName = userDisplayName
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                    LibraryHeader(presentSave: presentSave)

                    LibraryGreeting(displayName: userDisplayName)

                    LibrarySearchEntry {
                        selectedTab = .search
                    }

                    DiscoverShortcutsRow { path.append(.discover($0)) }

                    sourceFilters

                    content
                }
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .padding(.top, CentraliaTheme.Spacing.small)
                .padding(.bottom, CentraliaTheme.Spacing.xLarge)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .foregroundStyle(Color.centraliaInk)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
                    .toolbar(.hidden, for: .tabBar)
            }
            .task(id: offlineStatus?.syncRevision) {
                viewModel.trackScreenViewed()
                if let revision = offlineStatus?.syncRevision, revision > 0 { await viewModel.retry() }
                else { await viewModel.load() }
            }
            .task(id: recentlyViewed?.revision) {
                let entries = await recentlyViewed?.recent(limit: RecentlyViewed.shownInLibrary) ?? []
                if !Task.isCancelled { recentEntries = entries }
            }
            .onChange(of: offlineStatus?.folderSnapshot) { _, folders in
                if let folders { viewModel.applyFolderSnapshot(folders) }
            }
            .alert("Couldn’t update your library", isPresented: failureBinding) {
                Button("OK") {
                    viewModel.dismissFailure()
                }
            } message: {
                Text(viewModel.failureMessage ?? FeatureError.genericMessage)
            }
            .sheet(item: $movingVideo) { video in
                MoveVideoSheet(video: video, folders: viewModel.folders) { folderID in
                    Task {
                        await viewModel.move(video, to: folderID)
                    }
                }
            }
            .confirmationDialog(
                "Delete this video?",
                isPresented: deletionDialogBinding,
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { video in
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.delete(video)
                    }
                }

                Button("Cancel", role: .cancel) {}
            } message: { video in
                Text("“\(video.displayTitle)” will be removed from your library.")
            }
            .overlay {
                if viewModel.recentlyDeletedVideo != nil {
                    // Shake to undo: the pop-up the backend sent with the delete.
                    ShakeToUndoPopup(
                        message: viewModel.undoDeletion?.undoMessage ?? VideoDeletion.defaultUndoMessage,
                        expiresAt: viewModel.undoDeletion?.undoExpiresAt
                    ) { method in
                        Task {
                            await viewModel.undoDelete(method: method)
                        }
                    } dismiss: {
                        viewModel.dismissUndo()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: viewModel.recentlyDeletedVideo?.id)
        }
    }

    private var sourceFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                ForEach(LibrarySourceFilter.allCases) { filter in
                    LibraryFilterChip(
                        filter: filter,
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        viewModel.selectedFilter = filter
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Filter library by platform")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading your library…")
                .frame(maxWidth: .infinity, minHeight: 280)

        case let .failed(message):
            ContentUnavailableView {
                Label("Library unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task {
                        await viewModel.retry()
                    }
                }
                .buttonStyle(CentraliaProminentButtonStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 320)

        case .loaded:
            if !viewModel.folders.isEmpty {
                folderShortcuts
            }
            if viewModel.videos.isEmpty {
                emptyLibrary
            } else {
                recentlyViewedRow

                if viewModel.filteredVideos.isEmpty {
                    ContentUnavailableView(
                        "No saved \(viewModel.selectedFilter.displayName)",
                        systemImage: "rectangle.stack",
                        description: Text("Choose another platform or save a new short.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    masonryFeed
                }
            }
        }
    }

    @ViewBuilder
    private var recentlyViewedRow: some View {
        let recent = RecentlyViewed.videos(for: recentEntries, in: viewModel.videos)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
                Text("Recently viewed")
                    .font(CentraliaTheme.Typography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: CentraliaTheme.Spacing.small) {
                        ForEach(recent) { item in
                            RecentlyViewedCard(video: item.video, viewCount: item.entry.viewCount) {
                                path.append(.video(VideoDetailRoute(video: item.video)))
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var folderShortcuts: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Text("Folders")
                .font(CentraliaTheme.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal) {
                HStack(spacing: CentraliaTheme.Spacing.small) {
                    ForEach(viewModel.folders) { folder in
                        FolderShortcut(
                            folder: folder,
                            itemCount: viewModel.videos.count { $0.folderID == folder.id }
                        ) {
                            path.append(.folder(folder))
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var masonryFeed: some View {
        LibraryVideoGrid(videos: viewModel.filteredVideos) { video, index in
            videoCard(video, styleIndex: index)
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Your library is ready", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Save a TikTok, Instagram Reel, or YouTube Short to see it here.")
        } actions: {
            Button("Save a Short", action: presentSave)
                .buttonStyle(CentraliaProminentButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    private func videoCard(_ video: VideoItem, styleIndex: Int) -> some View {
        LibraryVideoCard(
            video: video,
            styleIndex: styleIndex,
            openDetail: {
                path.append(.video(VideoDetailRoute(video: video)))
            },
            play: {
                path.append(.video(VideoDetailRoute(video: video, startsPlaying: true)))
            },
            requestMove: {
                movingVideo = video
            },
            requestDelete: {
                pendingDeletion = video
            }
        )
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .discover(.creators):
            CreatorsView(
                viewModel: CreatorsViewModel(
                    videoRepository: videoRepository,
                    cache: sprint4.creatorsCache,
                    analytics: sprint4.analytics
                ),
                openVideo: { path.append(.video(VideoDetailRoute(video: $0))) }
            )

        case .discover(.rediscover):
            RediscoverView(
                viewModel: RediscoverViewModel(
                    videoRepository: videoRepository,
                    recentlyViewed: recentlyViewed,
                    dismissals: sprint4.dismissals,
                    analytics: sprint4.analytics
                ),
                isOnline: offlineStatus?.isOnline ?? true,
                openVideo: { path.append(.video(VideoDetailRoute(video: $0))) }
            )

        case .discover(.trends):
            TrendsView(repository: sprint4.trends, analytics: sprint4.analytics)

        case .discover(.watchLater):
            WatchLaterView(
                viewModel: WatchLaterViewModel(
                    videoRepository: videoRepository,
                    store: sprint4.watchLater,
                    analytics: sprint4.analytics
                ),
                openVideo: { path.append(.video(VideoDetailRoute(video: $0))) }
            )

        case .discover(.insights):
            InsightsView(viewModel: InsightsViewModel(
                videoRepository: videoRepository,
                store: sprint4.insights,
                analytics: sprint4.analytics
            ))

        case let .video(route):
            VideoDetailView(
                video: route.video,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                playbackRepository: playbackRepository,
                analytics: analytics,
                startsPlaying: route.startsPlaying,
                videoChanged: { updatedVideo in
                    viewModel.apply(updatedVideo)
                },
                videoDeleted: { deletedVideo, deletion in
                    viewModel.registerDeleted(deletedVideo, deletion: deletion)
                }
            )

        case let .folder(folder):
            FolderDetailView(
                folder: folder,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                playbackRepository: playbackRepository,
                analytics: analytics,
                folderChanged: {
                    Task {
                        await viewModel.retry()
                    }
                }
            )
        }
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: { viewModel.failureMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissFailure()
                }
            }
        )
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }
}
