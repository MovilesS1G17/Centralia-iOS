import SwiftUI

struct SearchView: View {
    private enum Route: Hashable {
        case video(VideoItem)
    }

    @State private var viewModel: SearchViewModel
    @State private var path: [Route] = []
    @State private var playingVideoID: UUID?
    @State private var pendingDeletion: VideoItem?
    @State private var movingVideo: VideoItem?
    @FocusState private var searchIsFocused: Bool

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        searchHistoryRepository: any SearchHistoryRepository
    ) {
        _viewModel = State(
            initialValue: SearchViewModel(
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                searchHistoryRepository: searchHistoryRepository
            )
        )
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
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .video(video):
                    UpcomingFeatureView(
                        title: video.displayTitle,
                        screenNumber: 7,
                        systemImage: "play.rectangle",
                        detail: "Video Detail will be implemented in Screen 7."
                    )
                    .toolbar(.hidden, for: .tabBar)
                }
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

    private var searchArea: some View {
        VStack(spacing: CentraliaTheme.Spacing.small) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .accessibilityHidden(true)

                TextField("Search titles, creators, or tags", text: $viewModel.query)
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
                .buttonStyle(.borderedProminent)
                .tint(Color.centraliaInk)
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
            } else if viewModel.filteredVideos.isEmpty {
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
            .buttonStyle(.borderedProminent)
            .tint(Color.centraliaInk)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var resultsGrid: some View {
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

    private var selectedFolderTitle: String {
        switch viewModel.selectedFolder {
        case .all:
            "Folder"
        case .unorganized:
            "Unorganized"
        case let .folder(folderID):
            viewModel.folderName(for: folderID) ?? "Folder"
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
