import SwiftUI

struct SaveConfirmationView: View {
    @State private var viewModel: SaveConfirmationViewModel
    @State private var showsNoteEditor = false
    @State private var showsVideoDetail = false
    @State private var folderName: String?

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let videoUpdated: () -> Void
    private let done: () -> Void

    init(
        video: VideoItem,
        folderName: String?,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        videoUpdated: @escaping () -> Void,
        done: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: SaveConfirmationViewModel(
                video: video,
                videoRepository: videoRepository
            )
        )
        _folderName = State(initialValue: folderName)
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.videoUpdated = videoUpdated
        self.done = done
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CentraliaTheme.Spacing.xLarge) {
                successStatus
                videoSummary
                actions
            }
            .padding(.horizontal, CentraliaTheme.Spacing.medium)
            .padding(.top, CentraliaTheme.Spacing.xxLarge)
            .padding(.bottom, CentraliaTheme.Spacing.xLarge)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color.centraliaCanvas.ignoresSafeArea())
        .foregroundStyle(Color.centraliaInk)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsNoteEditor) {
            SaveConfirmationNoteSheet(
                viewModel: viewModel,
                noteSaved: videoUpdated
            )
        }
        .navigationDestination(isPresented: $showsVideoDetail) {
            VideoDetailView(
                video: viewModel.video,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                videoChanged: { updatedVideo in
                    viewModel.replaceVideo(updatedVideo)
                    Task {
                        let folders = try? await folderRepository.folders()
                        folderName = updatedVideo.folderID.flatMap { folderID in
                            folders?.first { $0.id == folderID }?.name
                        }
                    }
                    videoUpdated()
                },
                videoDeleted: { _ in
                    videoUpdated()
                    done()
                }
            )
        }
        .alert("Couldn’t save note", isPresented: failureBinding) {
            Button("OK") {
                viewModel.dismissFailure()
            }
        } message: {
            Text(viewModel.failureMessage ?? "Please try again.")
        }
    }

    private var successStatus: some View {
        VStack(spacing: CentraliaTheme.Spacing.large) {
            Image(systemName: "checkmark")
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(Color.centraliaCanvas)
                .frame(width: 108, height: 108)
                .background(Color.centraliaInk, in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: CentraliaTheme.Spacing.small) {
                Text("Saved to Centralia")
                    .font(CentraliaTheme.Typography.display)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("saveConfirmationTitle")

                Text(viewModel.video.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.centraliaSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var videoSummary: some View {
        HStack(alignment: .top, spacing: CentraliaTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(thumbnailColor)

                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.centraliaInk, in: Circle())
            }
            .frame(width: 92, height: 144)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text("\(viewModel.video.platform.displayName) · \(viewModel.video.formattedDuration)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.centraliaSecondaryText)

                Text(viewModel.video.creator)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)

                Label(
                    folderName ?? "No Folder Select",
                    systemImage: folderName == nil ? "folder.badge.questionmark" : "folder"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.centraliaSecondaryText)
                .accessibilityIdentifier("saveConfirmationFolder")

                if !viewModel.video.tags.isEmpty {
                    FlowLayout(spacing: CentraliaTheme.Spacing.small) {
                        ForEach(viewModel.video.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.centraliaInk)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 30)
                                .background(Color.centraliaSoftSurface, in: Capsule())
                                .overlay {
                                    Capsule().stroke(Color.centraliaDivider, lineWidth: 1)
                                }
                                .fixedSize(horizontal: true, vertical: false)
                                .accessibilityIdentifier("saveConfirmationTag_\(tag)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(CentraliaTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.centraliaDivider, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("saveConfirmationSummary")
    }

    private var actions: some View {
        VStack(spacing: CentraliaTheme.Spacing.small) {
            Button("View Video") {
                showsVideoDetail = true
            }
            .font(.headline)
            .foregroundStyle(Color.centraliaCanvas)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.centraliaInk, in: RoundedRectangle(cornerRadius: 16))
            .buttonStyle(CentraliaPressStyle())

            if viewModel.shouldShowAddNote {
                Button("Add Note") {
                    showsNoteEditor = true
                }
                .font(.headline)
                .foregroundStyle(Color.centraliaInk)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.centraliaDivider, lineWidth: 1)
                }
                .buttonStyle(CentraliaPressStyle())
            }

            Button("Done") {
                done()
            }
            .font(.headline)
            .foregroundStyle(Color.centraliaInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .buttonStyle(CentraliaPressStyle())
        }
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

}

private struct SaveConfirmationNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SaveConfirmationViewModel
    @State private var note = ""
    @FocusState private var noteIsFocused: Bool

    let noteSaved: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
                Text("Personal note")
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    if note.isEmpty {
                        Text("Why is this short worth remembering?")
                            .foregroundStyle(Color.centraliaSecondaryText)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 17)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $note)
                        .focused($noteIsFocused)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 180)
                        .accessibilityLabel("Personal note")
                        .accessibilityIdentifier("confirmationNoteField")
                }
                .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.centraliaDivider, lineWidth: 1)
                }

                Spacer()
            }
            .padding(CentraliaTheme.Spacing.medium)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isSavingNote)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSavingNote ? "Saving…" : "Save") {
                        saveNote()
                    }
                    .disabled(
                        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || viewModel.isSavingNote
                    )
                }
            }
            .onAppear {
                noteIsFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(viewModel.isSavingNote)
    }

    private func saveNote() {
        Task {
            guard await viewModel.saveNote(note) else { return }
            noteSaved()
            dismiss()
        }
    }
}
