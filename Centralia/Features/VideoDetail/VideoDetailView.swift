import SwiftUI

struct VideoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel: VideoDetailViewModel
    @State private var isPlaying = false
    @State private var showsTagEditor = false
    @State private var showsFolderPicker = false
    @State private var showsNoteEditor = false
    @State private var showsReportForm = false
    @State private var showsDeleteConfirmation = false
    @State private var showsOpenFailure = false
    @State private var showsReportConfirmation = false

    private let videoChanged: (VideoItem) -> Void
    private let videoDeleted: (VideoItem) -> Void

    init(
        video: VideoItem,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        videoChanged: @escaping (VideoItem) -> Void = { _ in },
        videoDeleted: @escaping (VideoItem) -> Void = { _ in }
    ) {
        _viewModel = State(
            initialValue: VideoDetailViewModel(
                video: video,
                videoRepository: videoRepository,
                folderRepository: folderRepository
            )
        )
        self.videoChanged = videoChanged
        self.videoDeleted = videoDeleted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                preview
                metadata
                organization
                note
                actions
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
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Video")
                    .font(CentraliaTheme.Typography.sectionTitle)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ShareLink(
                        item: viewModel.video.sourceURL,
                        subject: Text(viewModel.video.displayTitle),
                        message: Text("\(viewModel.video.displayTitle) — \(viewModel.video.creator)")
                    ) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }

                    Button("Report", systemImage: "exclamationmark.bubble") {
                        showsReportForm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More video actions")
            }
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showsTagEditor) {
            VideoTagEditorSheet(viewModel: viewModel) {
                videoChanged(viewModel.video)
            }
        }
        .sheet(isPresented: $showsFolderPicker) {
            MoveVideoSheet(video: viewModel.video, folders: viewModel.folders) { folderID in
                Task {
                    guard await viewModel.move(to: folderID) else { return }
                    videoChanged(viewModel.video)
                }
            }
        }
        .sheet(isPresented: $showsNoteEditor) {
            VideoNoteEditorSheet(viewModel: viewModel) {
                videoChanged(viewModel.video)
            }
        }
        .sheet(isPresented: $showsReportForm) {
            VideoReportSheet {
                showsReportConfirmation = true
            }
        }
        .confirmationDialog(
            "Delete this video?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteVideo()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(viewModel.video.displayTitle)” will be removed from your library.")
        }
        .alert("Couldn’t open this video", isPresented: $showsOpenFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The original link is still saved in Centralia. Try again when the source is available.")
        }
        .alert("Report sent", isPresented: $showsReportConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Thanks. This mock report has been recorded for the demo session.")
        }
        .alert("Couldn’t update video", isPresented: failureBinding) {
            Button("OK") {
                viewModel.dismissFailure()
            }
        } message: {
            Text(viewModel.failureMessage ?? "Please try again.")
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Loading video details")
            }
        }
    }

    private var preview: some View {
        ZStack {
            thumbnailColor

            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Color.centraliaInk.opacity(0.95), in: Circle())
            }
            .buttonStyle(CentraliaPressStyle())
            .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")

            Text(viewModel.video.platform.displayName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .frame(minHeight: 38)
                .background(Color.centraliaSurface.opacity(0.94), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(CentraliaTheme.Spacing.medium)

            Text(viewModel.video.formattedDuration)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Color.centraliaInk.opacity(0.88), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(CentraliaTheme.Spacing.medium)
        }
        .frame(maxWidth: 410)
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("videoDetailPreview")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Text(viewModel.video.displayTitle)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("videoDetailTitle")

            Text("\(viewModel.video.creator) · Saved \(viewModel.video.savedAt.formatted(.dateTime.month(.abbreviated).day()))")
                .font(.headline)
                .foregroundStyle(Color.centraliaSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Label(
                viewModel.folderName ?? "No Folder Selected",
                systemImage: viewModel.video.folderID == nil ? "folder.badge.questionmark" : "folder"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.centraliaSecondaryText)
            .accessibilityIdentifier("videoDetailFolder")
        }
    }

    @ViewBuilder
    private var organization: some View {
        if viewModel.video.tags.isEmpty {
            Button("Add Tags", systemImage: "plus") {
                showsTagEditor = true
            }
            .font(.headline)
            .foregroundStyle(Color.centraliaInk)
            .frame(minHeight: 44)
            .accessibilityIdentifier("videoDetailAddTags")
        } else {
            FlowLayout(spacing: CentraliaTheme.Spacing.small) {
                ForEach(Array(viewModel.video.tags.enumerated()), id: \.offset) { index, tag in
                    Button(tag) {
                        showsTagEditor = true
                    }
                    .font(.headline)
                    .foregroundStyle(index == 0 ? Color.white : Color.centraliaInk)
                    .padding(.horizontal, CentraliaTheme.Spacing.medium)
                    .frame(minHeight: 44)
                    .background(
                        index == 0 ? Color.centraliaInk : Color.centraliaSoftSurface,
                        in: Capsule()
                    )
                    .overlay {
                        if index != 0 {
                            Capsule().stroke(Color.centraliaDivider, lineWidth: 1)
                        }
                    }
                    .buttonStyle(CentraliaPressStyle())
                    .accessibilityHint("Opens the tag editor")
                    .accessibilityIdentifier("videoDetailTag_\(tag)")
                }
            }
        }
    }

    private var note: some View {
        Button {
            showsNoteEditor = true
        } label: {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
                HStack {
                    Text("Personal note")
                        .font(CentraliaTheme.Typography.sectionTitle)
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundStyle(Color.centraliaSecondaryText)
                }

                Text(viewModel.video.note ?? "Add a personal note.")
                    .font(.body)
                    .foregroundStyle(
                        viewModel.video.note == nil ? Color.centraliaSecondaryText : Color.centraliaInk
                    )
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the note editor")
    }

    private var actions: some View {
        VStack(spacing: CentraliaTheme.Spacing.medium) {
            Button(viewModel.openActionTitle) {
                openSourceVideo()
            }
            .font(.headline)
            .foregroundStyle(Color.centraliaCanvas)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.centraliaInk, in: RoundedRectangle(cornerRadius: 16))
            .buttonStyle(CentraliaPressStyle())
            .accessibilityIdentifier("videoDetailOpenSource")

            HStack(spacing: CentraliaTheme.Spacing.small) {
                Button("Edit Tags") {
                    showsTagEditor = true
                }
                .accessibilityIdentifier("videoDetailEditTags")

                Spacer(minLength: 0)

                Button(viewModel.folderActionTitle) {
                    showsFolderPicker = true
                }
                .accessibilityIdentifier("videoDetailFolderAction")

                Spacer(minLength: 0)

                Button("Delete", role: .destructive) {
                    showsDeleteConfirmation = true
                }
                .accessibilityIdentifier("videoDetailDelete")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(viewModel.isMutating)
    }

    private var thumbnailColor: Color {
        switch viewModel.video.platform {
        case .tiktok:
            .centraliaVideoSand
        case .instagramReel:
            .centraliaVideoMint
        case .youtubeShort:
            .centraliaVideoClay
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

    private func openSourceVideo() {
        openURL(viewModel.video.sourceURL) { accepted in
            if !accepted {
                showsOpenFailure = true
            }
        }
    }

    private func deleteVideo() {
        let deletedVideo = viewModel.video
        Task {
            guard await viewModel.deleteVideo() else { return }
            videoDeleted(deletedVideo)
            dismiss()
        }
    }
}

private struct VideoTagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: VideoDetailViewModel
    @State private var selectedTags: [String]
    @State private var newTag = ""
    @FocusState private var newTagIsFocused: Bool

    let tagsSaved: () -> Void

    init(viewModel: VideoDetailViewModel, tagsSaved: @escaping () -> Void) {
        self.viewModel = viewModel
        _selectedTags = State(initialValue: viewModel.video.tags)
        self.tagsSaved = tagsSaved
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Selected tags") {
                    if selectedTags.isEmpty {
                        Text("No tags selected")
                            .foregroundStyle(Color.centraliaSecondaryText)
                    } else {
                        ForEach(selectedTags, id: \.self) { tag in
                            Button {
                                remove(tag)
                            } label: {
                                Label(tag, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(Color.centraliaInk)
                            }
                            .accessibilityHint("Removes this tag")
                        }
                    }
                }

                Section("Add a tag") {
                    HStack {
                        TextField("New tag", text: $newTag)
                            .focused($newTagIsFocused)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .onSubmit(addNewTag)
                            .accessibilityIdentifier("videoDetailNewTagField")

                        Button("Add", action: addNewTag)
                            .disabled(trimmedNewTag.isEmpty)
                    }
                }

                if !unselectedAvailableTags.isEmpty {
                    Section("Available tags") {
                        ForEach(unselectedAvailableTags, id: \.self) { tag in
                            Button {
                                selectedTags.append(tag)
                            } label: {
                                Label(tag, systemImage: "plus.circle")
                                    .foregroundStyle(Color.centraliaInk)
                            }
                            .accessibilityHint("Adds this tag")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.centraliaCanvas)
            .navigationTitle("Edit Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isMutating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isMutating ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(viewModel.isMutating)
                    .accessibilityIdentifier("videoDetailSaveTags")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(viewModel.isMutating)
    }

    private var trimmedNewTag: String {
        newTag.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var unselectedAvailableTags: [String] {
        viewModel.availableTags.filter { availableTag in
            !selectedTags.contains {
                $0.localizedCaseInsensitiveCompare(availableTag) == .orderedSame
            }
        }
    }

    private func addNewTag() {
        let tag = trimmedNewTag
        guard !tag.isEmpty else { return }
        if !selectedTags.contains(where: {
            $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
        }) {
            selectedTags.append(tag)
        }
        newTag = ""
    }

    private func remove(_ tag: String) {
        selectedTags.removeAll {
            $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
        }
    }

    private func save() {
        Task {
            guard await viewModel.updateTags(selectedTags) else { return }
            tagsSaved()
            dismiss()
        }
    }
}

private struct VideoNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: VideoDetailViewModel
    @State private var note: String
    @FocusState private var noteIsFocused: Bool

    let noteSaved: () -> Void

    init(viewModel: VideoDetailViewModel, noteSaved: @escaping () -> Void) {
        self.viewModel = viewModel
        _note = State(initialValue: viewModel.video.note ?? "")
        self.noteSaved = noteSaved
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
                Text("Personal note")
                    .font(.headline)

                TextEditor(text: $note)
                    .focused($noteIsFocused)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.centraliaDivider, lineWidth: 1)
                    }
                    .accessibilityIdentifier("videoDetailNoteField")

                Spacer()
            }
            .padding(CentraliaTheme.Spacing.medium)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .navigationTitle(viewModel.video.note == nil ? "Add Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isMutating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isMutating ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(viewModel.isMutating)
                }
            }
            .onAppear {
                noteIsFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(viewModel.isMutating)
    }

    private func save() {
        Task {
            guard await viewModel.updateNote(note) else { return }
            noteSaved()
            dismiss()
        }
    }
}

private struct VideoReportSheet: View {
    private enum IssueType: String, CaseIterable, Identifiable {
        case broken = "Video is unavailable"
        case metadata = "Metadata is incorrect"
        case other = "Something else"

        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var issue: IssueType = .broken
    @State private var details = ""

    let submitted: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("What went wrong?") {
                    Picker("Issue", selection: $issue) {
                        ForEach(IssueType.allCases) { issue in
                            Text(issue.rawValue).tag(issue)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Details (optional)") {
                    TextField("Tell us what happened", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.centraliaCanvas)
            .navigationTitle("Report Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        dismiss()
                        submitted()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
