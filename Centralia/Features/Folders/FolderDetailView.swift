import SwiftUI

struct FolderDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: FolderDetailViewModel
    @State private var selectedVideo: VideoItem?
    @State private var movingVideo: VideoItem?
    @State private var pendingDeletion: VideoItem?
    @State private var showsRenameFolder = false
    @State private var showsTagFilter = false
    @State private var showsDeleteFolderConfirmation = false
    @FocusState private var searchIsFocused: Bool

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let folderChanged: () -> Void

    init(
        folder: LibraryFolder,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        folderChanged: @escaping () -> Void = {}
    ) {
        _viewModel = State(
            initialValue: FolderDetailViewModel(
                folder: folder,
                videoRepository: videoRepository,
                folderRepository: folderRepository
            )
        )
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.folderChanged = folderChanged
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                header
                searchField
                sourceFilters
                content
            }
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .padding(.top, CentraliaTheme.Spacing.small)
            .padding(.bottom, CentraliaTheme.Spacing.xLarge)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .background(Color.centraliaCanvas.ignoresSafeArea())
        .foregroundStyle(Color.centraliaInk)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
        .navigationDestination(item: $selectedVideo) { video in
            VideoDetailView(
                video: video,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                videoChanged: { updatedVideo in
                    viewModel.apply(updatedVideo)
                    folderChanged()
                },
                videoDeleted: { deletedVideo in
                    viewModel.registerDeleted(deletedVideo)
                    folderChanged()
                }
            )
            .toolbar(.hidden, for: .tabBar)
        }
        .sheet(item: $movingVideo) { video in
            MoveVideoSheet(video: video, folders: viewModel.folders) { folderID in
                Task {
                    await viewModel.move(video, to: folderID)
                    folderChanged()
                }
            }
        }
        .sheet(isPresented: $showsRenameFolder) {
            FolderRenameSheet(viewModel: viewModel) {
                folderChanged()
            }
        }
        .sheet(isPresented: $showsTagFilter) {
            FolderTagsSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Remove this short from your library?",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { video in
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.delete(video)
                    folderChanged()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { video in
            Text("“\(video.displayTitle)” will be removed from your library.")
        }
        .confirmationDialog(
            "Delete \(viewModel.folder.name)?",
            isPresented: $showsDeleteFolderConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                Task {
                    guard await viewModel.deleteFolder() else { return }
                    folderChanged()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its shorts will remain in Unorganized.")
        }
        .alert("Couldn’t update folder", isPresented: failureBinding) {
            Button("OK") { viewModel.dismissFailure() }
        } message: {
            Text(viewModel.failureMessage ?? "Please try again.")
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.recentlyDeletedVideo != nil {
                LibraryUndoToast {
                    Task {
                        await viewModel.undoDelete()
                        folderChanged()
                    }
                } dismiss: {
                    viewModel.dismissUndo()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.recentlyDeletedVideo?.id)
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
            .accessibilityIdentifier("folderDetailBack")

            Text(viewModel.folder.name)
                .font(CentraliaTheme.Typography.display)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Menu {
                Button("Rename Folder", systemImage: "pencil") {
                    showsRenameFolder = true
                }
                Button("Delete Folder", systemImage: "trash", role: .destructive) {
                    showsDeleteFolderConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Folder actions")
            .accessibilityIdentifier("folderDetailMoreActions")
        }
    }

    private var searchField: some View {
        HStack(spacing: CentraliaTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(Color.centraliaSecondaryText)
                .accessibilityHidden(true)

            TextField("Search in \(viewModel.folder.name)", text: $viewModel.query)
                .font(.body)
                .focused($searchIsFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("folderDetailSearchField")

            if !viewModel.query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    viewModel.query = ""
                    searchIsFocused = true
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.centraliaSecondaryText)
                .accessibilityIdentifier("folderDetailClearSearch")
            }
        }
        .padding(.horizontal, CentraliaTheme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    searchIsFocused ? Color.centraliaInk : Color.centraliaDivider,
                    lineWidth: searchIsFocused ? 2 : 1
                )
        }
        .accessibilityElement(children: .contain)
    }

    private var sourceFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                ForEach(LibrarySourceFilter.allCases) { filter in
                    LibraryFilterChip(
                        filter: filter,
                        isSelected: viewModel.selectedSourceFilter == filter
                    ) {
                        viewModel.selectedSourceFilter = filter
                    }
                }

                Button {
                    showsTagFilter = true
                } label: {
                    HStack(spacing: 6) {
                        Text(tagFilterTitle)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(
                        viewModel.selectedTags.isEmpty
                            ? Color.centraliaInk
                            : Color.centraliaCanvas
                    )
                    .padding(.horizontal, CentraliaTheme.Spacing.medium)
                    .frame(minHeight: 44)
                    .background(
                        viewModel.selectedTags.isEmpty
                            ? Color.centraliaSoftSurface
                            : Color.centraliaInk,
                        in: Capsule()
                    )
                    .overlay {
                        if viewModel.selectedTags.isEmpty {
                            Capsule()
                                .stroke(Color.centraliaDivider, lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(CentraliaPressStyle())
                .accessibilityLabel(tagFilterAccessibilityLabel)
                .accessibilityIdentifier("folderDetailTags")
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Filter folder by platform or tags")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading folder…")
                .frame(maxWidth: .infinity, minHeight: 320)

        case let .failed(message):
            ContentUnavailableView {
                Label("Folder unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.centraliaInk)
            }
            .frame(maxWidth: .infinity, minHeight: 320)

        case .loaded:
            resultControls

            if viewModel.filteredVideos.isEmpty {
                ContentUnavailableView {
                    Label("No matching shorts", systemImage: "rectangle.stack")
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if hasActiveFilters {
                        Button("Clear Filters") { clearFilters() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.centraliaInk)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                videoGrid
            }
        }
    }

    private var resultControls: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(viewModel.filteredVideos.count) saved \(viewModel.filteredVideos.count == 1 ? "short" : "shorts")")
                .font(.headline)
                .foregroundStyle(Color.centraliaSecondaryText)

            Spacer(minLength: CentraliaTheme.Spacing.small)

            Menu {
                Picker("Sort", selection: $viewModel.sort) {
                    ForEach(FolderSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Text("Sort")
                    .font(.headline)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("folderDetailSort")

        }
    }

    private var videoGrid: some View {
        let videos = viewModel.filteredVideos
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                FolderDetailVideoCard(video: video, styleIndex: index) {
                    selectedVideo = video
                } requestMove: {
                    movingVideo = video
                } requestDelete: {
                    pendingDeletion = video
                }
            }
        }
        .accessibilityIdentifier("folderDetailVideoGrid")
    }

    private var emptyDescription: String {
        if viewModel.videos.isEmpty {
            return "Move a saved short here to build this folder."
        }
        return "Try another search or filter."
    }

    private var hasActiveFilters: Bool {
        !viewModel.query.isEmpty
            || viewModel.selectedSourceFilter != .all
            || !viewModel.selectedTags.isEmpty
    }

    private var tagFilterTitle: String {
        let count = viewModel.selectedTags.count
        return count == 0 ? "Tags" : "Tags (\(count))"
    }

    private var tagFilterAccessibilityLabel: String {
        let count = viewModel.selectedTags.count
        return count == 0 ? "Filter by tags" : "Filter by tags, \(count) selected"
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented { pendingDeletion = nil }
            }
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

    private func clearFilters() {
        viewModel.query = ""
        viewModel.selectedSourceFilter = .all
        viewModel.selectedTags = []
    }
}

private struct FolderDetailVideoCard: View {
    let video: VideoItem
    let styleIndex: Int
    let open: () -> Void
    let requestMove: () -> Void
    let requestDelete: () -> Void

    private let cardHeight: CGFloat = 270

    private var cardColor: Color {
        [
            .centraliaVideoClay,
            .centraliaVideoMint,
            .centraliaVideoSand,
            .centraliaVideoLavender
        ][styleIndex % 4]
    }

    var body: some View {
        ZStack {
            Button(action: open) {
                cardColor
                    .contentShape(RoundedRectangle(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(video.displayTitle)")

            Text(video.platform.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.centraliaInk)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(Color.centraliaSurface.opacity(0.96), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .accessibilityHidden(true)

            Button(action: open) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.centraliaInk.opacity(0.92), in: Circle())
            }
            .buttonStyle(CentraliaPressStyle())
            .accessibilityLabel("Open \(video.displayTitle)")

            Text(video.formattedDuration)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(Color.centraliaInk.opacity(0.84), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(12)
                .padding(.bottom, 61)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.displayTitle)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text(video.creator)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.centraliaSecondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(12)
            .padding(.trailing, 28)
            .allowsHitTesting(false)

            Menu {
                Button("Move to Folder", systemImage: "folder") { requestMove() }
                ShareLink(
                    item: video.sourceURL,
                    subject: Text(video.displayTitle),
                    message: Text("\(video.displayTitle) — \(video.creator)")
                ) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    requestDelete()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .tint(Color.centraliaSecondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(3)
            .accessibilityLabel("More actions for \(video.displayTitle)")
        }
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("folderVideoCard.\(video.id.uuidString)")
    }
}

private struct FolderRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: FolderDetailViewModel
    @State private var name = ""
    @FocusState private var nameIsFocused: Bool

    let renamed: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
                Text("Rename this collection without changing its saved shorts.")
                    .font(.body)
                    .foregroundStyle(Color.centraliaSecondaryText)

                TextField("Folder name", text: $name)
                    .focused($nameIsFocused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, CentraliaTheme.Spacing.medium)
                    .frame(minHeight: 56)
                    .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.centraliaDivider, lineWidth: 1)
                    }
                    .onSubmit(save)
                    .accessibilityIdentifier("renameFolderNameField")

                if let message = viewModel.failureMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(CentraliaTheme.Spacing.medium)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .navigationTitle("Rename Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = viewModel.folder.name
                nameIsFocused = true
            }
            .onDisappear { viewModel.dismissFailure() }
        }
        .presentationDetents([.height(300)])
    }

    private func save() {
        Task {
            guard await viewModel.renameFolder(to: name) else { return }
            renamed()
            dismiss()
        }
    }
}

private struct FolderTagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: FolderDetailViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Tags in \(viewModel.folder.name)") {
                    if viewModel.availableTags.isEmpty {
                        Text("No tags in this folder yet.")
                            .foregroundStyle(Color.centraliaSecondaryText)
                    } else {
                        ForEach(viewModel.availableTags, id: \.self) { tag in
                            Button {
                                toggle(tag)
                            } label: {
                                HStack {
                                    Text(tag)
                                    Spacer()
                                    if viewModel.selectedTags.contains(tag) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .foregroundStyle(Color.centraliaInk)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.centraliaCanvas)
            .navigationTitle("Filter by Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        viewModel.selectedTags = []
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ tag: String) {
        if viewModel.selectedTags.contains(tag) {
            viewModel.selectedTags.remove(tag)
        } else {
            viewModel.selectedTags.insert(tag)
        }
    }
}
