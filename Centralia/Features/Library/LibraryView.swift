import SwiftUI

struct LibraryView: View {
    private enum Route: Hashable {
        case video(VideoItem)
        case folder(LibraryFolder)
    }

    @State private var viewModel: LibraryViewModel
    @Binding private var selectedTab: AppTab
    @State private var path: [Route] = []
    @State private var playingVideoID: UUID?
    @State private var pendingDeletion: VideoItem?
    @State private var movingVideo: VideoItem?

    private let presentSave: () -> Void
    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        selectedTab: Binding<AppTab>,
        presentSave: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: LibraryViewModel(
                videoRepository: videoRepository,
                folderRepository: folderRepository
            )
        )
        _selectedTab = selectedTab
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.presentSave = presentSave
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                    LibraryHeader(presentSave: presentSave)

                    LibrarySearchEntry {
                        selectedTab = .search
                    }

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
            .task {
                await viewModel.load()
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
            .safeAreaInset(edge: .bottom) {
                if viewModel.recentlyDeletedVideo != nil {
                    LibraryUndoToast {
                        Task {
                            await viewModel.undoDelete()
                        }
                    } dismiss: {
                        viewModel.dismissUndo()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .buttonStyle(.borderedProminent)
                .tint(Color.centraliaInk)
            }
            .frame(maxWidth: .infinity, minHeight: 320)

        case .loaded:
            if viewModel.videos.isEmpty {
                emptyLibrary
            } else {
                folderShortcuts

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
        let entries = Array(viewModel.filteredVideos.enumerated())
        let leftEntries = entries.filter { $0.offset.isMultiple(of: 2) }
        let rightEntries = entries.filter { !$0.offset.isMultiple(of: 2) }

        return HStack(alignment: .top, spacing: 12) {
            LazyVStack(spacing: 12) {
                ForEach(leftEntries, id: \.element.id) { index, video in
                    videoCard(video, styleIndex: index)
                }
            }

            LazyVStack(spacing: 12) {
                ForEach(rightEntries, id: \.element.id) { index, video in
                    videoCard(video, styleIndex: index)
                }
            }
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Your library is ready", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("Save a TikTok, Instagram Reel, or YouTube Short to see it here.")
        } actions: {
            Button("Save a Short", action: presentSave)
                .buttonStyle(.borderedProminent)
                .tint(Color.centraliaInk)
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    private func videoCard(_ video: VideoItem, styleIndex: Int) -> some View {
        LibraryVideoCard(
            video: video,
            styleIndex: styleIndex,
            isPlaying: playingVideoID == video.id,
            openDetail: {
                path.append(.video(video))
            },
            togglePlayback: {
                playingVideoID = playingVideoID == video.id ? nil : video.id
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
        case let .video(video):
            VideoDetailView(
                video: video,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                videoChanged: { updatedVideo in
                    viewModel.apply(updatedVideo)
                },
                videoDeleted: { deletedVideo in
                    viewModel.registerDeleted(deletedVideo)
                }
            )

        case let .folder(folder):
            FolderDetailView(
                folder: folder,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                folderChanged: {
                    Task {
                        await viewModel.retry()
                    }
                }
            )
        }
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
