import SwiftUI

struct BatchImportView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorIsFocused: Bool
    @State private var model: BatchImportViewModel
    @State private var action: Action?
    @State private var showsDiscardConfirmation = false

    private let libraryChanged: () -> Void
    private let done: () -> Void

    private enum Action { case review, checkRemaining, save }

    init(
        pipeline: any VideoImportPipeline,
        videoRepository: any VideoItemRepository,
        libraryChanged: @escaping () -> Void,
        done: @escaping () -> Void
    ) {
        _model = State(initialValue: BatchImportViewModel(pipeline: pipeline, videoRepository: videoRepository))
        self.libraryChanged = libraryChanged
        self.done = done
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                if model.phase == .editing {
                    editor
                } else {
                    review
                }
            }
            .padding(CentraliaTheme.Spacing.medium)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.centraliaCanvas.ignoresSafeArea())
        .foregroundStyle(Color.centraliaInk)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back", systemImage: "chevron.left", action: goBack)
                    .labelStyle(.iconOnly)
                    .disabled(model.phase == .saving || action == .save)
            }
            if model.phase == .reviewing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit Links", action: model.editLinks)
                        .disabled(action != nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .confirmationDialog("Discard pending links?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Pending Links", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Shorts you’ve already saved are in Unorganized.")
        }
        .task(id: action) {
            guard let action else { return }
            switch action {
            case .review: await model.reviewInput()
            case .checkRemaining: await model.checkRemaining()
            case .save:
                if await model.saveReady() { libraryChanged() }
            }
            if !Task.isCancelled { self.action = nil }
        }
    }

    private var editor: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
            heading("Import multiple links")
            Text("Paste up to \(BatchImportViewModel.linkLimit) TikTok, Instagram Reel, or YouTube Short links, one per line.")
                .foregroundStyle(Color.centraliaSecondaryText)

            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
                TextEditor(text: $model.input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .focused($editorIsFocused)
                    .padding(10)
                    .frame(minHeight: 184)
                    .overlay(alignment: .topLeading) {
                        if model.input.isEmpty {
                            Text("https://www.youtube.com/shorts/…")
                                .foregroundStyle(Color.centraliaSecondaryText)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(editorIsFocused ? Color.centraliaInk : Color.centraliaDivider, lineWidth: editorIsFocused ? 2 : 1)
                            .allowsHitTesting(false)
                    }
                    .accessibilityLabel("Short video links")
                    .accessibilityHint("Enter one link per line")
                    .accessibilityIdentifier("batchImportLinks")

                if model.linkCount > BatchImportViewModel.linkLimit {
                    Text("Keep \(BatchImportViewModel.linkLimit) links or fewer to continue.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.centraliaError)
                } else {
                    Text("\(model.linkCount) / \(BatchImportViewModel.linkLimit) links")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.centraliaSecondaryText)
                }
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
                heading(model.savedCount > 0 && !model.hasPendingWork && model.phase == .reviewing
                        ? "Import complete" : "Review links")
                if model.phase == .checking {
                    ProgressView(value: Double(model.checkedCount), total: Double(model.rows.count)) {
                        Text("\(model.checkedCount) of \(model.rows.count) links reviewed")
                    }
                    .tint(.centraliaInk)
                    .accessibilityIdentifier("batchImportProgress")
                } else if model.savedCount > 0 {
                    Text("\(model.savedCount) saved to Unorganized")
                        .accessibilityIdentifier("batchImportSavedCount")
                } else if model.saveableCount > 0 {
                    Text("Ready links will be saved to Unorganized.")
                }
            }
            .foregroundStyle(Color.centraliaSecondaryText)

            ForEach(model.rows) { row in
                BatchImportRow(row: row)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: CentraliaTheme.Spacing.small) {
            switch model.phase {
            case .editing:
                primaryButton("Check Links", id: "batchImportCheck", enabled: model.canReviewInput && action == nil) {
                    editorIsFocused = false
                    action = .review
                }
            case .checking:
                secondaryButton("Stop Checking", id: "batchImportStop") { action = nil }
                    .disabled(action == nil)
            case .saving:
                ProgressView("Saving to Unorganized…")
                    .tint(.centraliaInk)
                    .frame(minHeight: 44)
            case .reviewing:
                if model.saveableCount > 0 {
                    primaryButton("Save \(model.saveableCount) to Unorganized", id: "batchImportSave", enabled: action == nil) {
                        action = .save
                    }
                }
                if model.checkableCount > 0 {
                    secondaryButton("Check Remaining Links", id: "batchImportRetryChecking") { action = .checkRemaining }
                        .disabled(action != nil)
                }
                if !model.hasPendingWork {
                    primaryButton("Done", id: "batchImportDone", enabled: action == nil, action: done)
                }
            }
        }
        .padding(.horizontal, CentraliaTheme.Spacing.medium)
        .padding(.vertical, CentraliaTheme.Spacing.small)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(Color.centraliaCanvas)
        .overlay(alignment: .top) { Divider().overlay(Color.centraliaDivider).allowsHitTesting(false) }
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(CentraliaTheme.Typography.display)
            .foregroundStyle(Color.centraliaInk)
            .accessibilityAddTraits(.isHeader)
    }

    private func primaryButton(_ title: LocalizedStringKey, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .padding(.vertical, CentraliaTheme.Spacing.small)
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(enabled ? Color.centraliaCanvas : Color.centraliaSecondaryText)
                .background(enabled ? Color.centraliaInk : Color.centraliaSoftSurface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(CentraliaPressStyle())
        .accessibilityIdentifier(id)
        .disabled(!enabled)
    }

    private func secondaryButton(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .buttonStyle(CentraliaPressStyle())
            .accessibilityIdentifier(id)
    }

    private func goBack() {
        if model.phase == .editing ? model.linkCount > 0 : model.hasPendingWork {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}

private struct BatchImportRow: View {
    let row: BatchImportViewModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            if let video = row.status.video {
                Text(video.platform.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.centraliaSecondaryText)
                Text(video.displayTitle)
                    .font(.headline)
                    .lineLimit(3)
                Text(video.creatorDisplayName)
                    .foregroundStyle(Color.centraliaSecondaryText)
                    .font(.subheadline)
            } else {
                Text(row.source)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            status
                .font(.subheadline.weight(.medium))
        }
        .padding(CentraliaTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.centraliaDivider, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("batchImportRow.\(row.id)")
    }

    @ViewBuilder
    private var status: some View {
        switch row.status {
        case .waiting:
            Label("Waiting to check", systemImage: "clock")
                .foregroundStyle(Color.centraliaSecondaryText)
        case .checking:
            ProgressView("Checking…")
        case .repeatedLink:
            Label("Duplicate in this batch", systemImage: "square.on.square")
                .foregroundStyle(Color.centraliaSecondaryText)
        case .ready:
            Label("Ready to save", systemImage: "checkmark.circle")
        case .saving:
            ProgressView("Saving…")
        case .saved:
            Label("Saved to Unorganized", systemImage: "checkmark.circle.fill")
        case .alreadySaved:
            Label("Already in your library", systemImage: "bookmark")
                .foregroundStyle(Color.centraliaSecondaryText)
        case let .checkFailed(failure), let .saveFailed(_, failure):
            Label(failure.message, systemImage: "exclamationmark.circle")
                .foregroundStyle(Color.centraliaError)
        }
    }
}
