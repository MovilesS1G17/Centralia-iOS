import SwiftUI

struct SaveImportStatusCard: View {
    let metadata: ImportedVideoMetadata?
    let stage: VideoImportStage?
    let errorMessage: String?

    var body: some View {
        HStack(spacing: CentraliaTheme.Spacing.medium) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                if let errorMessage {
                    Label("Link not supported", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color.centraliaSecondaryText)
                } else if let metadata {
                    Text("\(metadata.platform.displayName) detected")
                        .font(.headline)
                    Text("\(metadata.creator) · \(metadata.formattedDuration)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.centraliaSecondaryText)

                    if let stage {
                        processingLabel(stage)
                    } else {
                        Label("Metadata ready", systemImage: "checkmark")
                            .font(.subheadline)
                            .foregroundStyle(Color.centraliaSecondaryText)
                    }
                } else if let stage {
                    Text(stage.displayName)
                        .font(.headline)
                    stageProgress(stage)
                }
            }

            Spacer(minLength: 0)

            if errorMessage == nil, stage == nil {
                Image(systemName: "checkmark")
                    .font(.title3.weight(.semibold))
                    .accessibilityHidden(true)
            } else if stage != nil {
                ProgressView()
                    .tint(Color.centraliaInk)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.centraliaSoftSurface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("saveVideoImportStatus")
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(thumbnailColor)
                .frame(width: 76, height: 102)

            Circle()
                .fill(Color.centraliaInk)
                .frame(width: 42, height: 42)

            Image(systemName: errorMessage == nil ? "play.fill" : "link")
                .font(.body.weight(.bold))
                .foregroundStyle(Color.centraliaSurface)
                .offset(x: errorMessage == nil ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    private var thumbnailColor: Color {
        switch metadata?.platform {
        case .tiktok:
            .centraliaVideoSand
        case .instagramReel:
            .centraliaVideoMint
        case .youtubeShort:
            .centraliaVideoClay
        case nil:
            .centraliaDivider
        }
    }

    private func processingLabel(_ stage: VideoImportStage) -> some View {
        Text(stage.displayName)
            .font(.subheadline)
            .foregroundStyle(Color.centraliaSecondaryText)
    }

    private func stageProgress(_ stage: VideoImportStage) -> some View {
        HStack(spacing: 5) {
            ForEach(VideoImportStage.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= stage.rawValue ? Color.centraliaInk : Color.centraliaDivider)
                    .frame(width: 22, height: 4)
            }
        }
        .accessibilityLabel("Step \(stage.rawValue + 1) of \(VideoImportStage.allCases.count)")
    }
}

struct SaveTagChip: View {
    let tag: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
            Button("Remove \(tag)", systemImage: "xmark") {
                remove()
            }
            .labelStyle(.iconOnly)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.centraliaCanvas)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(minHeight: 44)
        .background(Color.centraliaInk, in: Capsule())
    }
}

struct SaveFolderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SaveVideoViewModel
    @State private var newFolderName = ""
    @State private var selectedFolderSymbol = FolderSymbol.folder
    @FocusState private var newFolderIsFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Destination") {
                    folderButton(name: "Unorganized", symbolName: "tray", folderID: nil)

                    ForEach(viewModel.folders) { folder in
                        folderButton(
                            name: folder.name,
                            symbolName: folder.symbolName,
                            folderID: folder.id
                        )
                    }
                }

                Section("New Folder") {
                    TextField("Folder name", text: $newFolderName)
                        .focused($newFolderIsFocused)
                        .submitLabel(.done)
                        .onSubmit(createFolder)
                        .accessibilityIdentifier("newFolderNameField")

                    FolderSymbolPicker(selection: $selectedFolderSymbol)

                    Button("Create and Select", systemImage: "folder.badge.plus") {
                        createFolder()
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let message = viewModel.folderFailureMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(message)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.centraliaCanvas)
            .navigationTitle("Choose a folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                viewModel.dismissFolderFailure()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func folderButton(
        name: String,
        symbolName: String,
        folderID: UUID?
    ) -> some View {
        Button {
            viewModel.selectedFolderID = folderID
            dismiss()
        } label: {
            HStack {
                Label(name, systemImage: symbolName)
                Spacer()
                if viewModel.selectedFolderID == folderID {
                    Image(systemName: "checkmark")
                }
            }
        }
        .foregroundStyle(Color.centraliaInk)
    }

    private func createFolder() {
        Task {
            guard await viewModel.createFolder(
                named: newFolderName,
                symbol: selectedFolderSymbol
            ) != nil else { return }
            dismiss()
        }
    }
}

struct SaveTagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SaveVideoViewModel
    @State private var tag = ""
    @FocusState private var tagIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Add your own tag") {
                    TextField("Tag", text: $tag)
                        .focused($tagIsFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addManualTag)
                        .accessibilityIdentifier("newTagField")

                    Button("Add Tag", systemImage: "plus") {
                        addManualTag()
                    }
                    .disabled(tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !viewModel.availableTagSuggestions.isEmpty {
                    Section {
                        ForEach(viewModel.availableTagSuggestions, id: \.self) { suggestion in
                            Button(suggestion, systemImage: "plus.circle") {
                                viewModel.addTag(suggestion)
                            }
                            .foregroundStyle(Color.centraliaInk)
                        }
                    } header: {
                        Text("Suggestions")
                    } footer: {
                        Text("Suggestions are never added automatically.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.centraliaCanvas)
            .navigationTitle("Add tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                tagIsFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func addManualTag() {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { return }
        viewModel.addTag(trimmedTag)
        tag = ""
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = layout(subviews: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? result.width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func layout(subviews: Subviews, width: CGFloat) -> CGSize {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            measuredWidth = max(measuredWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: measuredWidth, height: y + rowHeight)
    }
}
