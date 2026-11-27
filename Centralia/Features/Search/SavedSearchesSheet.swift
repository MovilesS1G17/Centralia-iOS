import SwiftUI

struct SavedSearchesSheet: View {
    enum Entry: Identifiable {
        case browse
        case create(VideoSearchCriteria)

        var id: String {
            switch self {
            case .browse: "browse"
            case .create: "create"
            }
        }
    }

    private enum Editor {
        case create(VideoSearchCriteria)
        case rename(SavedSearch)

        var criteria: VideoSearchCriteria {
            switch self {
            case let .create(criteria): criteria
            case let .rename(search): search.criteria
            }
        }
    }

    private enum LoadState {
        case loading, loaded([SavedSearch]), failed
    }

    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading
    @State private var editor: Editor?
    @State private var name: String
    @State private var isWriting = false
    @State private var saveError: String?
    @State private var pendingDeletion: SavedSearch?
    @State private var deletionFailed = false

    private let store: SavedSearchStore
    private let userID: UUID
    private let folderLabel: (UUID) -> String
    private let apply: (SavedSearch) -> Void

    init(
        entry: Entry,
        store: SavedSearchStore,
        userID: UUID,
        folderLabel: @escaping (UUID) -> String,
        apply: @escaping (SavedSearch) -> Void
    ) {
        self.store = store
        self.userID = userID
        self.folderLabel = folderLabel
        self.apply = apply

        switch entry {
        case .browse:
            _editor = State(initialValue: nil)
            _name = State(initialValue: "")
        case let .create(criteria):
            _editor = State(initialValue: .create(criteria))
            let query = criteria.text.trimmingCharacters(in: .whitespacesAndNewlines)
            _name = State(initialValue: query.isEmpty ? Self.filterLabels(for: criteria, folderLabel: folderLabel).first ?? "" : query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let editor {
                    nameForm(for: editor)
                } else {
                    listContent
                        .task {
                            if case .loading = state { await load() }
                        }
                }
            }
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .foregroundStyle(Color.centraliaInk)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if editor == nil {
                        Button("Done") { dismiss() }
                            .disabled(isWriting)
                    } else {
                        Button("Cancel", role: .cancel) {
                            if case .create = editor {
                                dismiss()
                            } else {
                                editor = nil
                                saveError = nil
                            }
                        }
                        .disabled(isWriting)
                    }
                }
                if let editor {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save(editor) } }
                            .disabled(isWriting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("commitSavedSearchName")
                    }
                }
            }
            .confirmationDialog(
                "Delete saved search?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { search in
                Button("Delete", role: .destructive) { Task { await delete(search) } }
                Button("Cancel", role: .cancel) {}
            } message: { search in
                Text("“\(search.name)” will be removed from Saved Searches.")
            }
            .alert("Couldn’t delete saved search", isPresented: $deletionFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Centralia couldn’t update saved searches on this device. Try again.")
            }
        }
        .interactiveDismissDisabled(isWriting)
    }

    private var title: String {
        switch editor {
        case .create: "Save Search"
        case .rename: "Rename Search"
        case nil: "Saved Searches"
        }
    }

    private func nameForm(for editor: Editor) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
                Text("Name")
                    .font(.headline)
                TextField(centralia: "Search name", text: $name)
                    .submitLabel(.done)
                    .onSubmit {
                        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Task { await save(editor) }
                        }
                    }
                    .padding(.horizontal, CentraliaTheme.Spacing.medium)
                    .frame(minHeight: 52)
                    .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.centraliaDivider, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .disabled(isWriting)
                    .accessibilityIdentifier("savedSearchName")

                Text(summary(for: editor.criteria))
                    .font(.subheadline)
                    .foregroundStyle(Color.centraliaSecondaryText)

                if isWriting {
                    ProgressView("Saving search…")
                } else if let saveError {
                    Label(saveError, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Color.centraliaError)
                }
            }
            .padding(CentraliaTheme.Spacing.medium)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        switch state {
        case .loading:
            ProgressView("Loading saved searches…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView {
                Label("Saved searches unavailable", systemImage: "exclamationmark.circle")
            } description: {
                Text("Centralia couldn’t open your saved searches on this device.")
            } actions: {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(CentraliaProminentButtonStyle())
            }
        case let .loaded(searches) where searches.isEmpty:
            ContentUnavailableView(
                "No saved searches",
                systemImage: "bookmark",
                description: Text("Save a query or a set of filters from Search to use it again here.")
            )
        case let .loaded(searches):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
                    ForEach(searches) { search in
                        row(for: search)
                    }
                    Text("Saved on this device and available offline.")
                        .font(.footnote)
                        .foregroundStyle(Color.centraliaSecondaryText)
                        .padding(.horizontal, CentraliaTheme.Spacing.small)
                }
                .padding(CentraliaTheme.Spacing.medium)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func row(for search: SavedSearch) -> some View {
        HStack(spacing: 0) {
            Button {
                apply(search)
                dismiss()
            } label: {
                HStack(spacing: CentraliaTheme.Spacing.small) {
                    Image(systemName: "bookmark")
                        .foregroundStyle(Color.centraliaInk)
                        .frame(width: 36, height: 36)
                        .background(Color.centraliaSoftSurface, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.xSmall) {
                        Text(search.name)
                            .font(.headline)
                        let details = summary(for: search.criteria, hidingQueryMatching: search.name)
                        if !details.isEmpty {
                            Text(details)
                                .font(.subheadline)
                                .foregroundStyle(Color.centraliaSecondaryText)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, CentraliaTheme.Spacing.small)
                .padding(.vertical, CentraliaTheme.Spacing.small)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(CentraliaPressStyle())
            .accessibilityHint("Apply this search and its filters")
            .accessibilityIdentifier("applySavedSearch.\(search.id)")

            Menu {
                Button("Rename", systemImage: "pencil") {
                    name = search.name
                    saveError = nil
                    editor = .rename(search)
                }
                Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = search }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Actions for \(search.name)")
        }
        .padding(.horizontal, CentraliaTheme.Spacing.small)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.centraliaDivider, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .disabled(isWriting)
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await store.searches(for: userID))
        } catch {
            state = .failed
        }
    }

    private func save(_ draft: Editor) async {
        guard !isWriting else { return }
        isWriting = true
        saveError = nil
        defer { isWriting = false }
        do {
            let updated: [SavedSearch]
            switch draft {
            case let .create(criteria):
                updated = try await store.create(named: name, criteria: criteria, for: userID)
            case let .rename(search):
                updated = try await store.rename(search.id, to: name, for: userID)
            }
            state = .loaded(updated)
            editor = nil
        } catch let error as SavedSearchStore.StoreError {
            saveError = error.localizedDescription
        } catch {
            saveError = "Centralia couldn’t save this search on this device. Try again."
        }
    }

    private func delete(_ search: SavedSearch) async {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }
        do {
            state = .loaded(try await store.remove(search.id, for: userID))
        } catch {
            deletionFailed = true
        }
    }

    private func summary(for criteria: VideoSearchCriteria, hidingQueryMatching name: String? = nil) -> String {
        let text = criteria.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = !text.isEmpty && text != name ? ["“\(text)”"] : []
        return (query + Self.filterLabels(for: criteria, folderLabel: folderLabel)).joined(separator: " · ")
    }

    private static func filterLabels(for criteria: VideoSearchCriteria, folderLabel: (UUID) -> String) -> [String] {
        let folder: String?
        switch criteria.folder {
        case .all: folder = nil
        case .unorganized: folder = "Unorganized"
        case let .folder(id): folder = folderLabel(id)
        }
        return [criteria.platform?.displayName, criteria.creator, folder].compactMap { $0 }
            + criteria.tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
