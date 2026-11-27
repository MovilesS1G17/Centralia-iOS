import SwiftUI

struct SearchView: View {
    @Environment(\.offlineLibraryStatus) private var offlineStatus
    @State private var viewModel: SearchViewModel
    @State private var path: [VideoDetailRoute] = []
    @State private var pendingDeletion: VideoItem?
    @State private var movingVideo: VideoItem?
    @State private var savedSearchEntry: SavedSearchesSheet.Entry?
    @FocusState private var searchIsFocused: Bool

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let analytics: any AnalyticsTracking
    private let playbackRepository: (any VideoPlaybackRepository)?
    private let savedSearchStore: SavedSearchStore
    private let userID: UUID

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        searchHistoryRepository: any SearchHistoryRepository,
        savedSearchStore: SavedSearchStore,
        userID: UUID,
        playbackRepository: (any VideoPlaybackRepository)? = nil,
        analytics: any AnalyticsTracking = NoOpAnalyticsTracking()
    ) {
        _viewModel = State(
            initialValue: SearchViewModel(
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                searchHistoryRepository: searchHistoryRepository,
                analytics: analytics
            )
        )
        self.analytics = analytics
        self.playbackRepository = playbackRepository
        self.savedSearchStore = savedSearchStore
        self.userID = userID
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                    Text("Search")
                        .font(CentraliaTheme.Typography.display)
                        .accessibilityAddTraits(.isHeader)

                    searchArea

                    filterMenus

                    savedSearchActions

                    if viewModel.selectedFolderIsUnavailable {
                        unavailableFolder
                    }

                    content
                }
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .padding(.top, CentraliaTheme.Spacing.medium)
                .padding(.bottom, CentraliaTheme.Spacing.xLarge)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .foregroundStyle(Color.centraliaInk)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: VideoDetailRoute.self) { route in
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
                .toolbar(.hidden, for: .tabBar)
            }
            .task(id: offlineStatus?.syncRevision) {
                viewModel.trackScreenViewed()
                if let revision = offlineStatus?.syncRevision, revision > 0 { await viewModel.retry() }
                else { await viewModel.load() }
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
            .sheet(item: $savedSearchEntry) { entry in
                SavedSearchesSheet(
                    entry: entry,
                    store: savedSearchStore,
                    userID: userID,
                    folderLabel: { id in
                        viewModel.folderName(for: id) ?? (viewModel.state == .loaded ? "Folder unavailable" : "Folder filter")
                    },
                    apply: viewModel.applySavedSearch
                )
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

    private var searchArea: some View {
        VStack(spacing: CentraliaTheme.Spacing.small) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .accessibilityHidden(true)

                TextField(centralia: "Search titles, creators, or tags", text: $viewModel.query)
                    .font(.body)
                    .focused($searchIsFocused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("globalSearchField")
                    .onSubmit {
                        Task {
                            await viewModel.submitSearch()
                        }
                    }

                if !viewModel.query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") {
                        viewModel.query = ""
                        searchIsFocused = true
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Color.centraliaSecondaryText)
                }
            }
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        searchIsFocused ? Color.centraliaInk : Color.centraliaDivider,
                        lineWidth: searchIsFocused ? 2 : 1
                    )
            }

            if showsRecentSearches {
                recentSearchMenu
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: showsRecentSearches)
    }

    private var showsRecentSearches: Bool {
        searchIsFocused && viewModel.query.isEmpty && !viewModel.recentSearches.isEmpty
    }

    private var recentSearchMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent searches")
                    .font(.headline)

                Spacer()

                Button("Clear History") {
                    Task {
                        await viewModel.clearRecentSearches()
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .padding(.vertical, CentraliaTheme.Spacing.small)

            ForEach(viewModel.recentSearches, id: \.self) { search in
                Button {
                    Task {
                        await viewModel.selectRecentSearch(search)
                        searchIsFocused = false
                    }
                } label: {
                    Label(search, systemImage: "clock.arrow.circlepath")
                        .font(.body)
                        .foregroundStyle(Color.centraliaInk)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
            }
        }
        .padding(.vertical, CentraliaTheme.Spacing.small)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.centraliaDivider, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent searches")
    }

    private var filterMenus: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                platformMenu
                creatorMenu
                folderMenu
                tagsMenu

                if viewModel.hasActiveFilters {
                    Button("Clear filters", systemImage: "xmark") {
                        viewModel.clearFilters()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.centraliaInk)
                    .frame(minHeight: 44)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Search filters")
    }

    private var savedSearchActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CentraliaTheme.Spacing.medium) {
                savedSearchesButton.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                saveSearchButton.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.xSmall) {
                savedSearchesButton
                saveSearchButton
            }
        }
    }

    private var savedSearchesButton: some View {
        Button {
            searchIsFocused = false
            savedSearchEntry = .browse
        } label: {
            Label("Saved Searches", systemImage: "bookmark")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(CentraliaPressStyle())
        .accessibilityIdentifier("openSavedSearches")
    }

    private var saveSearchButton: some View {
        Button {
            searchIsFocused = false
            savedSearchEntry = .create(viewModel.criteria)
        } label: {
            Label("Save Search", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(viewModel.criteria.isSaveable ? Color.centraliaCanvas : Color.centraliaSecondaryText)
                .background(viewModel.criteria.isSaveable ? Color.centraliaInk : Color.centraliaSoftSurface, in: Capsule())
        }
        .buttonStyle(CentraliaPressStyle())
        .disabled(!viewModel.criteria.isSaveable)
        .accessibilityIdentifier("saveCurrentSearch")
    }

    private var unavailableFolder: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.xSmall) {
            Label("The selected folder is unavailable.", systemImage: "folder.badge.questionmark")
                .font(.subheadline)
                .foregroundStyle(Color.centraliaSecondaryText)
            Button("Clear Folder Filter") { viewModel.selectedFolder = .all }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .buttonStyle(CentraliaPressStyle())
        }
        .accessibilityIdentifier("savedSearchUnavailableFolder")
    }

    private var platformMenu: some View {
        Menu {
            selectionButton(
                "All Platforms",
                isSelected: viewModel.selectedPlatform == nil
            ) {
                viewModel.selectedPlatform = nil
            }

            ForEach(VideoPlatform.allCases) { platform in
                selectionButton(
                    platform.displayName,
                    isSelected: viewModel.selectedPlatform == platform
                ) {
                    viewModel.selectedPlatform = platform
                }
            }
        } label: {
            SearchFilterMenuLabel(
                title: viewModel.selectedPlatform?.filterName ?? "Platform",
                isActive: viewModel.selectedPlatform != nil
            )
        }
        .accessibilityLabel("Platform filter")
        .accessibilityValue(viewModel.selectedPlatform?.displayName ?? "All platforms")
    }

    private var creatorMenu: some View {
        Menu {
            selectionButton(
                "All Creators",
                isSelected: viewModel.selectedCreator == nil
            ) {
                viewModel.selectedCreator = nil
            }

            ForEach(viewModel.availableCreators, id: \.self) { creator in
                selectionButton(
                    creator,
                    isSelected: viewModel.selectedCreator == creator
                ) {
                    viewModel.selectedCreator = creator
                }
            }
        } label: {
            SearchFilterMenuLabel(
                title: viewModel.selectedCreator ?? "Creator",
                isActive: viewModel.selectedCreator != nil
            )
        }
        .accessibilityLabel("Creator filter")
        .accessibilityValue(viewModel.selectedCreator ?? "All creators")
    }

    private var folderMenu: some View {
        Menu {
            selectionButton(
                "All Folders",
                isSelected: viewModel.selectedFolder == .all
            ) {
                viewModel.selectedFolder = .all
            }

            selectionButton(
                "Unorganized",
                isSelected: viewModel.selectedFolder == .unorganized
            ) {
                viewModel.selectedFolder = .unorganized
            }

            ForEach(viewModel.folders) { folder in
                selectionButton(
                    folder.name,
                    isSelected: viewModel.selectedFolder == .folder(folder.id)
                ) {
                    viewModel.selectedFolder = .folder(folder.id)
                }
            }
        } label: {
            SearchFilterMenuLabel(
                title: selectedFolderTitle,
                isActive: viewModel.selectedFolder != .all
            )
        }
        .accessibilityLabel("Folder filter")
        .accessibilityValue(viewModel.selectedFolder == .all ? "All folders" : selectedFolderTitle)
    }

    private var tagsMenu: some View {
        Menu {
            if !viewModel.selectedTags.isEmpty {
                Button("Clear Tags", systemImage: "xmark") {
                    viewModel.selectedTags.removeAll()
                }

                Divider()
            }

            ForEach(viewModel.availableTags, id: \.self) { tag in
                selectionButton(
                    tag,
                    isSelected: viewModel.selectedTags.contains(tag)
                ) {
                    viewModel.toggleTag(tag)
                }
            }
        } label: {
            SearchFilterMenuLabel(
                title: selectedTagsTitle,
                isActive: !viewModel.selectedTags.isEmpty
            )
        }
        .accessibilityLabel("Tags filter")
        .accessibilityValue(viewModel.selectedTags.isEmpty ? "All tags" : selectedTagsTitle)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Searching your library…")
                .frame(maxWidth: .infinity, minHeight: 280)

        case let .failed(message):
            ContentUnavailableView {
                Label("Search unavailable", systemImage: "exclamationmark.triangle")
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
            results
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shorts in your library")
                    .font(CentraliaTheme.Typography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Text(resultCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color.centraliaSecondaryText)
                    .accessibilityLabel(resultCountLabel)
            }

            if viewModel.videos.isEmpty {
                ContentUnavailableView(
                    "No saved shorts",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Save a short before searching your library.")
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            } else if viewModel.filteredVideos.isEmpty && !viewModel.selectedFolderIsUnavailable {
                noResults
            } else {
                resultsGrid
            }
        }
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label("No shorts found", systemImage: "magnifyingglass")
        } description: {
            Text("Try another title, creator, folder, or tag.")
        } actions: {
            Button("Clear Search and Filters") {
                viewModel.clearSearch()
                searchIsFocused = true
            }
            .buttonStyle(CentraliaProminentButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var resultsGrid: some View {
        LibraryVideoGrid(videos: viewModel.filteredVideos) { video, index in
            videoCard(video, styleIndex: index)
        }
    }

    private var selectedFolderTitle: String {
        switch viewModel.selectedFolder {
        case .all:
            "Folder"
        case .unorganized:
            "Unorganized"
        case let .folder(folderID):
            viewModel.folderName(for: folderID) ?? (viewModel.selectedFolderIsUnavailable ? "Folder unavailable" : "Folder")
        }
    }

    private var selectedTagsTitle: String {
        switch viewModel.selectedTags.count {
        case 0:
            "Tags"
        case 1:
            viewModel.selectedTags.first ?? "1 Tag"
        default:
            "\(viewModel.selectedTags.count) Tags"
        }
    }

    private var resultCountLabel: String {
        let count = viewModel.filteredVideos.count
        return "\(count) \(count == 1 ? "short" : "shorts")"
    }

    private func videoCard(_ video: VideoItem, styleIndex: Int) -> some View {
        let stableStyleIndex = viewModel.videos.firstIndex { $0.id == video.id } ?? styleIndex

        return LibraryVideoCard(
            video: video,
            styleIndex: stableStyleIndex,
            openDetail: {
                path.append(VideoDetailRoute(video: video))
            },
            play: {
                path.append(VideoDetailRoute(video: video, startsPlaying: true))
            },
            requestMove: {
                movingVideo = video
            },
            requestDelete: {
                pendingDeletion = video
            }
        )
    }

    private func selectionButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
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

private struct SearchFilterMenuLabel: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .lineLimit(1)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isActive ? Color.white : Color.centraliaInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                isActive ? Color.centraliaInk : Color.centraliaSoftSurface,
                in: Capsule()
            )
            .overlay {
                if !isActive {
                    Capsule()
                        .stroke(Color.centraliaDivider, lineWidth: 1)
                }
            }
    }
}
