import SwiftUI

struct SmartOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.offlineLibraryStatus) private var offlineStatus
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: SmartOrganizationViewModel
    @State private var changingSuggestion: FolderSuggestion?
    @State private var selectedVideo: VideoDetailRoute?
    @State private var refreshRequest: RefreshRequest?

    private struct RefreshRequest: Equatable {
        let id = UUID()
        let bypassCache: Bool
    }

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let playbackRepository: (any VideoPlaybackRepository)?
    private let libraryChanged: () -> Void

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        suggestionPipeline: any VideoImportPipeline,
        cache: FolderSuggestionCache,
        accountID: UUID,
        playbackRepository: (any VideoPlaybackRepository)? = nil,
        libraryChanged: @escaping () -> Void = {}
    ) {
        _viewModel = State(
            initialValue: SmartOrganizationViewModel(
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                suggestionPipeline: suggestionPipeline,
                cache: cache,
                accountID: accountID
            )
        )
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.playbackRepository = playbackRepository
        self.libraryChanged = libraryChanged
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                header
                organizationTools
                suggestionFeedback
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
        .task(id: refreshRequest) {
            if let request = refreshRequest {
                guard !viewModel.isMutating else { return }
                await viewModel.refresh(isOnline: { isOnline }, bypassCache: request.bypassCache)
                if !Task.isCancelled, refreshRequest == request { refreshRequest = nil }
            } else if viewModel.state == .idle {
                await viewModel.load(isOnline: { isOnline })
            }
        }
        .onChange(of: offlineStatus?.folderSnapshot) { _, folders in
            if let folders, viewModel.state == .loading || viewModel.updateFolders(folders) {
                refresh(bypassCache: false)
            }
        }
        .onChange(of: viewModel.isMutating) { _, busy in
            if !busy, let request = refreshRequest { refresh(bypassCache: request.bypassCache) }
        }
        .onChange(of: offlineStatus?.syncRevision) { _, _ in
            if viewModel.state == .loaded, !viewModel.isMutating { refresh(bypassCache: false) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, viewModel.state == .loaded, !viewModel.isMutating { refresh(bypassCache: false) }
        }
        .sheet(item: $changingSuggestion) { suggestion in
            SuggestionFolderPickerSheet(
                folders: viewModel.folders,
                suggestedFolderID: suggestion.folder.id
            ) { folder in
                Task {
                    guard await viewModel.move(suggestion, to: folder) else { return }
                    libraryChanged()
                }
            }
        }
        .navigationDestination(item: $selectedVideo) { route in
            VideoDetailView(
                video: route.video,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                playbackRepository: playbackRepository,
                startsPlaying: route.startsPlaying,
                videoChanged: { updatedVideo in
                    if viewModel.apply(updatedVideo) { refresh(bypassCache: false) }
                    libraryChanged()
                },
                videoDeleted: { deletedVideo, _ in
                    viewModel.registerDeleted(deletedVideo)
                    libraryChanged()
                }
            )
            .toolbar(.hidden, for: .tabBar)
        }
        .alert("Couldn’t organize this short", isPresented: failureBinding) {
            Button("OK") { viewModel.dismissFailure() }
        } message: {
            Text(viewModel.failureMessage ?? "Please try again.")
        }
    }

    private var isOnline: Bool { offlineStatus?.isOnline ?? true }

    private func refresh(bypassCache: Bool = true) {
        refreshRequest = RefreshRequest(bypassCache: bypassCache)
    }

    private var organizationTools: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: CentraliaTheme.Spacing.xSmall))
            : AnyLayout(HStackLayout(spacing: CentraliaTheme.Spacing.small))

        return layout {
            unorganizedCount
            if isOnline, viewModel.state == .loaded, viewModel.unorganizedCount > 0 {
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button("Refresh Suggestions", systemImage: "arrow.clockwise") { refresh() }
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 44)
                    .buttonStyle(CentraliaPressStyle())
                    .disabled(viewModel.isRefreshing || viewModel.isMutating)
                    .accessibilityIdentifier("refreshFolderSuggestions")
            }
        }
    }

    @ViewBuilder
    private var suggestionFeedback: some View {
        if viewModel.state == .loaded {
            let hasCached = !viewModel.cachedSuggestionIDs.isEmpty
            let hasOfflineMisses = !viewModel.connectionNeeded.isEmpty && !viewModel.suggestions.isEmpty
            let hasFailed = viewModel.refreshFailed || (!viewModel.failedLookups.isEmpty && !viewModel.suggestions.isEmpty)

            if hasCached || hasOfflineMisses || hasFailed || viewModel.isRefreshing {
                VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.xSmall) {
                    if hasCached {
                        Label(
                            viewModel.cachedSuggestionIDs.count == viewModel.suggestions.count ? "Saved suggestions" : "Includes saved suggestions",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("savedFolderSuggestions")
                    }
                    if hasOfflineMisses {
                        let count = viewModel.connectionNeeded.count
                        Text(count == 1 ? "1 short needs a connection for suggestions." : "\(count) shorts need a connection for suggestions.")
                            .font(.subheadline)
                            .foregroundStyle(Color.centraliaSecondaryText)
                    }
                    if hasFailed {
                        Text("Some suggestions couldn’t be updated. Try refreshing again.")
                            .font(.subheadline)
                            .foregroundStyle(Color.centraliaSecondaryText)
                    }
                    if viewModel.isRefreshing {
                        ProgressView("Refreshing suggestions…")
                            .font(.subheadline)
                    }
                }
                .padding(CentraliaTheme.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.centraliaSoftSurface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var header: some View {
        HStack(spacing: CentraliaTheme.Spacing.small) {
            Button("Back", systemImage: "chevron.left") {
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .frame(width: 44, height: 44)
            .buttonStyle(CentraliaPressStyle())
            .accessibilityIdentifier("smartOrganizationBack")

            Text("Organize")
                .font(CentraliaTheme.Typography.display)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
    }

    private var unorganizedCount: some View {
        Text("\(viewModel.unorganizedCount) unorganized \(viewModel.unorganizedCount == 1 ? "short" : "shorts")")
            .font(.headline)
            .foregroundStyle(Color.centraliaSecondaryText)
            .contentTransition(.numericText())
            .accessibilityIdentifier("smartOrganizationCount")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Preparing suggestions…")
                .frame(maxWidth: .infinity, minHeight: 440)

        case let .failed(message):
            ContentUnavailableView {
                Label("Suggestions unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    refresh(bypassCache: false)
                }
                .buttonStyle(CentraliaProminentButtonStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 440)

        case .loaded:
            if viewModel.suggestions.isEmpty, !viewModel.isRefreshing {
                completionState
            } else if !viewModel.suggestions.isEmpty {
                suggestionPager
                pageIndicator
                controlNotice
            }
        }
    }

    private var suggestionPager: some View {
        @Bindable var model = viewModel
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(viewModel.suggestions) { suggestion in
                    SmartSuggestionCard(
                        suggestion: suggestion,
                        isMutating: viewModel.isMutating || viewModel.isRefreshing,
                        openVideo: { selectedVideo = VideoDetailRoute(video: suggestion.video) },
                        playVideo: { selectedVideo = VideoDetailRoute(video: suggestion.video, startsPlaying: true) },
                        changeFolder: { changingSuggestion = suggestion },
                        accept: {
                            Task {
                                guard await viewModel.accept(suggestion) else { return }
                                libraryChanged()
                            }
                        },
                        skip: { viewModel.skip(suggestion) }
                    )
                    .padding(.horizontal, 2)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.selectedSuggestionID)
        .accessibilityIdentifier("smartOrganizationPager")
    }

    private var pageIndicator: some View {
        HStack(spacing: 12) {
            ForEach(Array(viewModel.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.selectedSuggestionID = suggestion.id
                    }
                } label: {
                    Circle()
                        .fill(
                            viewModel.selectedSuggestionID == suggestion.id
                                ? Color.centraliaInk
                                : Color.centraliaDivider
                        )
                        .frame(width: 10, height: 10)
                        .contentShape(Rectangle().inset(by: -12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suggestion \(index + 1) of \(viewModel.suggestions.count)")
                .accessibilityAddTraits(
                    viewModel.selectedSuggestionID == suggestion.id ? .isSelected : []
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("smartOrganizationPageIndicator")
    }

    private var controlNotice: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: CentraliaTheme.Spacing.small))
            : AnyLayout(HStackLayout(spacing: CentraliaTheme.Spacing.medium))

        return layout {
            Image(systemName: "sparkles")
                .font(.title2)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Suggestions stay under your control")
                    .font(.headline)
                Text("Nothing moves without your choice.")
                    .font(.subheadline)
                    .foregroundStyle(Color.centraliaSecondaryText)
            }
        }
        .padding(CentraliaTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.centraliaSoftSurface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var completionState: some View {
        let title: LocalizedStringKey
        let description: LocalizedStringKey
        let icon: String

        if viewModel.unorganizedCount == 0 {
            title = "Everything is organized"
            description = "Your Unorganized collection is empty."
            icon = "checkmark.circle"
        } else if !viewModel.connectionNeeded.isEmpty {
            title = "No saved suggestions"
            description = isOnline
                ? "Refresh to get suggestions for your unorganized shorts."
                : "Connect to the internet to get suggestions for your unorganized shorts."
            icon = "wifi.slash"
        } else if !viewModel.failedLookups.isEmpty {
            title = "Suggestions couldn’t load"
            description = "Refresh to try again."
            icon = "exclamationmark.circle"
        } else {
            title = "No suggestions left"
            description = viewModel.hasSkipped
                ? "Skipped shorts are still safe in Unorganized."
                : "There are no folder suggestions for these shorts."
            icon = "sparkles"
        }

        return ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(description)
        } actions: {
            Button("Back to Folders") { dismiss() }
                .buttonStyle(CentraliaProminentButtonStyle())
                .accessibilityIdentifier("smartOrganizationBackToFolders")
        }
        .frame(maxWidth: .infinity, minHeight: 440)
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: { viewModel.failureMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.dismissFailure() }
            }
        )
    }
}

private struct SmartSuggestionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let suggestion: FolderSuggestion
    let isMutating: Bool
    let openVideo: () -> Void
    let playVideo: () -> Void
    let changeFolder: () -> Void
    let accept: () -> Void
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview

            Button(action: openVideo) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.video.displayTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)

                    Text(suggestion.video.creator)
                        .font(.headline)
                        .foregroundStyle(Color.centraliaSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens video details")

            Text("Suggested folder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.centraliaSecondaryText)

            Button(action: changeFolder) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: CentraliaTheme.Spacing.small))
                    : AnyLayout(HStackLayout(spacing: CentraliaTheme.Spacing.medium))

                layout {
                    Label(suggestion.folder.name, systemImage: suggestion.folder.symbolName)
                        .font(.headline)
                        .multilineTextAlignment(.leading)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                    }

                    Text("Change")
                        .font(.headline)
                }
                .foregroundStyle(Color.centraliaInk)
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .padding(.vertical, CentraliaTheme.Spacing.small)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(Color.centraliaSoftSurface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(CentraliaPressStyle())
            .disabled(isMutating)
            .accessibilityLabel("Suggested folder \(suggestion.folder.name). Change folder")
            .accessibilityIdentifier("smartOrganizationChangeFolder")

            let actionsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))

            actionsLayout {
                Button("Accept", action: accept)
                    .font(.headline)
                    .padding(.horizontal, CentraliaTheme.Spacing.small)
                    .padding(.vertical, CentraliaTheme.Spacing.xSmall)
                    .foregroundStyle(Color.centraliaSurface)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.centraliaInk, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("smartOrganizationAccept")

                Button("Skip", action: skip)
                    .font(.headline)
                    .padding(.horizontal, CentraliaTheme.Spacing.small)
                    .padding(.vertical, CentraliaTheme.Spacing.xSmall)
                    .foregroundStyle(Color.centraliaInk)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.centraliaDivider, lineWidth: 1)
                    }
                    .accessibilityIdentifier("smartOrganizationSkip")
            }
            .buttonStyle(CentraliaPressStyle())
            .disabled(isMutating)
        }
        .padding(CentraliaTheme.Spacing.medium)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.centraliaDivider, lineWidth: 1)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("smartOrganizationSuggestion.\(suggestion.id.uuidString)")
    }

    private var preview: some View {
        ZStack {
            thumbnailColor
                .onTapGesture(perform: openVideo)

            Button(action: playVideo) {
                Image(systemName: "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.centraliaInk.opacity(0.94), in: Circle())
            }
            .buttonStyle(CentraliaPressStyle())
            .accessibilityLabel("Play \(suggestion.video.displayTitle)")

            Text(suggestion.video.platform.displayName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .frame(minHeight: 36)
                .background(Color.centraliaSurface.opacity(0.95), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(14)
                .accessibilityHidden(true)

            Text(suggestion.video.formattedDuration)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(Color.centraliaInk.opacity(0.84), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(14)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: 390)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(suggestion.video.platform.displayName), \(suggestion.video.formattedDuration)")
        .accessibilityHint("Double tap outside the play button to open video details")
    }

    private var thumbnailColor: Color {
        switch suggestion.video.platform {
        case .tiktok:
            .centraliaVideoSand
        case .instagramReel:
            .centraliaVideoMint
        case .youtubeShort:
            .centraliaVideoClay
        }
    }
}

private struct SuggestionFolderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let folders: [LibraryFolder]
    let suggestedFolderID: UUID
    let choose: (LibraryFolder) -> Void

    var body: some View {
        NavigationStack {
            List(folders) { folder in
                Button {
                    choose(folder)
                    dismiss()
                } label: {
                    HStack {
                        Label(folder.name, systemImage: folder.symbolName)
                        Spacer()
                        if folder.id == suggestedFolderID {
                            Image(systemName: "sparkles")
                                .accessibilityLabel("Suggested")
                        }
                    }
                }
                .foregroundStyle(Color.centraliaInk)
            }
            .scrollContentBackground(.hidden)
            .background(Color.centraliaCanvas)
            .navigationTitle("Choose Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
