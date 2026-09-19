import SwiftUI

struct SmartOrganizationView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: SmartOrganizationViewModel
    @State private var changingSuggestion: FolderSuggestion?
    @State private var selectedVideo: VideoItem?

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let libraryChanged: () -> Void

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        suggestionPipeline: any VideoImportPipeline,
        libraryChanged: @escaping () -> Void = {}
    ) {
        _viewModel = State(
            initialValue: SmartOrganizationViewModel(
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                suggestionPipeline: suggestionPipeline
            )
        )
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.libraryChanged = libraryChanged
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                header
                unorganizedCount
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
        .task {
            await viewModel.load()
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
        .navigationDestination(item: $selectedVideo) { video in
            VideoDetailView(
                video: video,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                videoChanged: { updatedVideo in
                    viewModel.apply(updatedVideo)
                    libraryChanged()
                },
                videoDeleted: { deletedVideo in
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
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.centraliaInk)
            }
            .frame(maxWidth: .infinity, minHeight: 440)

        case .loaded:
            if viewModel.suggestions.isEmpty {
                completionState
            } else {
                suggestionPager
                pageIndicator
                controlNotice
            }
        }
    }

    private var suggestionPager: some View {
        TabView(selection: suggestionSelection) {
            ForEach(viewModel.suggestions) { suggestion in
                SmartSuggestionCard(
                    suggestion: suggestion,
                    isMutating: viewModel.isMutating,
                    openVideo: { selectedVideo = suggestion.video },
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
                .tag(suggestion.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 490)
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
        HStack(spacing: CentraliaTheme.Spacing.medium) {
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
        ContentUnavailableView {
            Label(
                viewModel.unorganizedCount == 0 ? "Everything is organized" : "No suggestions left",
                systemImage: viewModel.unorganizedCount == 0 ? "checkmark.circle" : "sparkles"
            )
        } description: {
            Text(
                viewModel.unorganizedCount == 0
                    ? "Your Unorganized collection is empty."
                    : "Skipped shorts are still safe in Unorganized."
            )
        } actions: {
            Button("Back to Folders") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Color.centraliaInk)
                .accessibilityIdentifier("smartOrganizationBackToFolders")
        }
        .frame(maxWidth: .infinity, minHeight: 440)
    }

    private var suggestionSelection: Binding<UUID> {
        Binding(
            get: {
                viewModel.selectedSuggestionID
                    ?? viewModel.suggestions.first?.id
                    ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            },
            set: { viewModel.selectedSuggestionID = $0 }
        )
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
    let suggestion: FolderSuggestion
    let isMutating: Bool
    let openVideo: () -> Void
    let changeFolder: () -> Void
    let accept: () -> Void
    let skip: () -> Void

    @State private var isPlaying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview

            Button(action: openVideo) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.video.displayTitle)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
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
                HStack(spacing: CentraliaTheme.Spacing.medium) {
                    Image(systemName: suggestion.folder.symbolName)
                        .font(.title3.weight(.semibold))
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    Text(suggestion.folder.name)
                        .font(.headline)

                    Spacer(minLength: 0)

                    Text("Change")
                        .font(.headline)
                }
                .foregroundStyle(Color.centraliaInk)
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color.centraliaSoftSurface, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(CentraliaPressStyle())
            .disabled(isMutating)
            .accessibilityLabel("Suggested folder \(suggestion.folder.name). Change folder")
            .accessibilityIdentifier("smartOrganizationChangeFolder")

            HStack(spacing: 12) {
                Button("Accept", action: accept)
                    .font(.headline)
                    .foregroundStyle(Color.centraliaSurface)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Color.centraliaInk, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("smartOrganizationAccept")

                Button("Skip", action: skip)
                    .font(.headline)
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

            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.centraliaInk.opacity(0.94), in: Circle())
            }
            .buttonStyle(CentraliaPressStyle())
            .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")

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
