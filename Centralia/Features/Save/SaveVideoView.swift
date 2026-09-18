import SwiftUI

struct SaveVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SaveVideoViewModel
    @State private var showsFolderPicker = false
    @State private var showsTagEditor = false
    @State private var showsDiscardConfirmation = false
    @State private var savedVideo: VideoItem?
    @FocusState private var focusedField: Field?

    private let videoSaved: () -> Void
    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository

    private enum Field: Hashable {
        case url
        case note
    }

    init(
        pipeline: any VideoImportPipeline,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        videoSaved: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: SaveVideoViewModel(
                pipeline: pipeline,
                videoRepository: videoRepository,
                folderRepository: folderRepository
            )
        )
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.videoSaved = videoSaved
    }

    var body: some View {
        NavigationStack {
            if let savedVideo {
                SaveConfirmationView(
                    video: savedVideo,
                    folderName: viewModel.folders.first { $0.id == savedVideo.folderID }?.name,
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    videoUpdated: videoSaved,
                    done: { dismiss() }
                )
            } else {
                saveForm
            }
        }
        .interactiveDismissDisabled(viewModel.isDraftDirty && savedVideo == nil)
        .task {
            await viewModel.loadFolders()
        }
        .task(id: viewModel.urlText) {
            await viewModel.analyzeURL()
        }
        .sheet(isPresented: $showsFolderPicker) {
            SaveFolderPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showsTagEditor) {
            SaveTagEditorSheet(viewModel: viewModel)
        }
        .confirmationDialog(
            "Discard this draft?",
            isPresented: $showsDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Draft", role: .destructive) {
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("The pasted link and your organization choices will be lost.")
        }
        .alert(
            "Couldn’t save video",
            isPresented: saveFailureBinding
        ) {
            Button("Try Again") {
                save(organized: true)
            }
            Button("Cancel", role: .cancel) {
                viewModel.dismissSaveFailure()
            }
        } message: {
            Text(viewModel.saveFailureMessage ?? "Please try again.")
        }
    }

    private var saveForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                header
                urlSection

                if !viewModel.urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    importStatus
                }

                folderSection
                tagsSection
                noteSection
                saveActions
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
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Save Short Video")
                .font(CentraliaTheme.Typography.display)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button("Close") {
                close()
            }
            .font(.headline)
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Text("Paste a TikTok, Reel, or Short link")
                .font(.title3.weight(.bold))

            TextField("https://www.youtube.com/shorts/…", text: $viewModel.urlText)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focusedField, equals: .url)
                .font(.body)
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .frame(minHeight: 66)
                .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.centraliaInk, lineWidth: 2)
                }
                .accessibilityIdentifier("saveVideoURLField")
        }
    }

    @ViewBuilder
    private var importStatus: some View {
        switch viewModel.analysisState {
        case .idle:
            EmptyView()

        case let .processing(stage):
            SaveImportStatusCard(
                metadata: viewModel.metadata,
                stage: stage,
                errorMessage: nil
            )

        case .ready:
            SaveImportStatusCard(
                metadata: viewModel.metadata,
                stage: nil,
                errorMessage: nil
            )

        case let .failed(message):
            SaveImportStatusCard(
                metadata: nil,
                stage: nil,
                errorMessage: message
            )
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Text("Folder")
                .font(.headline)

            Button {
                showsFolderPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedFolderName ?? "Choose a folder")
                            .foregroundStyle(
                                viewModel.selectedFolderName == nil
                                    ? Color.centraliaSecondaryText
                                    : Color.centraliaInk
                            )

                        if let suggestion = viewModel.suggestedFolderName,
                           viewModel.selectedFolderName == suggestion {
                            Text("Suggested")
                                .font(.caption)
                                .foregroundStyle(Color.centraliaSecondaryText)
                        }
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.centraliaSecondaryText)
                }
                .font(.body)
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            viewModel.folderSelectionError == nil
                                ? Color.centraliaDivider
                                : Color.red,
                            lineWidth: 1
                        )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CentraliaPressStyle())
            .accessibilityIdentifier("saveVideoFolderPicker")

            if let errorMessage = viewModel.folderSelectionError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(errorMessage)")
                    .accessibilityIdentifier("saveVideoFolderError")
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Text("Tags")
                .font(.headline)

            FlowLayout(spacing: CentraliaTheme.Spacing.small) {
                ForEach(viewModel.selectedTags, id: \.self) { tag in
                    SaveTagChip(tag: tag) {
                        viewModel.removeTag(tag)
                    }
                }

                Button("Add tag", systemImage: "plus") {
                    showsTagEditor = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.centraliaInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.centraliaSoftSurface, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.centraliaDivider, lineWidth: 1)
                }
                .buttonStyle(CentraliaPressStyle())
                .accessibilityIdentifier("addVideoTagButton")
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            Text("Personal note")
                .font(.headline)

            ZStack(alignment: .topLeading) {
                if viewModel.note.isEmpty {
                    Text("Why is this short worth remembering?")
                        .foregroundStyle(Color.centraliaSecondaryText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 17)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $viewModel.note)
                    .focused($focusedField, equals: .note)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 124)
                    .accessibilityLabel("Personal note")
                    .accessibilityIdentifier("saveVideoNoteField")
            }
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.centraliaDivider, lineWidth: 1)
            }
        }
    }

    private var saveActions: some View {
        VStack(spacing: CentraliaTheme.Spacing.small) {
            Button {
                save(organized: true)
            } label: {
                Group {
                    if viewModel.isSaving {
                        ProgressView()
                            .tint(Color.centraliaCanvas)
                    } else {
                        Text("Save Video")
                    }
                }
                .font(.headline)
                .foregroundStyle(Color.centraliaCanvas)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color.centraliaInk, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(CentraliaPressStyle())
            .disabled(!viewModel.canSave)
            .opacity(viewModel.canSave ? 1 : 0.45)
            .accessibilityIdentifier("saveVideoButton")

            Button("Save without organizing") {
                save(organized: false)
            }
            .font(.headline)
            .foregroundStyle(Color.centraliaInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .buttonStyle(CentraliaPressStyle())
            .disabled(!viewModel.canSave)
            .opacity(viewModel.canSave ? 1 : 0.45)
            .accessibilityIdentifier("saveVideoUnorganizedButton")
        }
        .padding(.top, CentraliaTheme.Spacing.small)
    }

    private var saveFailureBinding: Binding<Bool> {
        Binding(
            get: { viewModel.saveFailureMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.dismissSaveFailure()
                }
            }
        )
    }

    private func close() {
        if viewModel.isDraftDirty {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func save(organized: Bool) {
        focusedField = nil
        Task {
            guard let video = await viewModel.save(organized: organized) else { return }
            videoSaved()
            savedVideo = video
        }
    }
}
