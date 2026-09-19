import SwiftUI

struct FoldersView: View {
    private enum Route: Hashable {
        case folder(LibraryFolder)
        case smartOrganization
    }

    @State private var viewModel: FoldersViewModel
    @State private var path: [Route] = []
    @State private var showsNewFolder = false
    @FocusState private var searchIsFocused: Bool

    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let suggestionPipeline: any VideoImportPipeline
    private let libraryChanged: () -> Void

    init(
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        suggestionPipeline: any VideoImportPipeline,
        libraryChanged: @escaping () -> Void = {}
    ) {
        _viewModel = State(
            initialValue: FoldersViewModel(
                videoRepository: videoRepository,
                folderRepository: folderRepository
            )
        )
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.suggestionPipeline = suggestionPipeline
        self.libraryChanged = libraryChanged
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                    header
                    folderSearchField
                    content
                }
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .padding(.top, CentraliaTheme.Spacing.medium)
                .padding(.bottom, CentraliaTheme.Spacing.xLarge)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .foregroundStyle(Color.centraliaInk)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .folder(folder):
                    FolderDetailView(
                        folder: folder,
                        videoRepository: videoRepository,
                        folderRepository: folderRepository,
                        folderChanged: {
                            Task { await viewModel.applyFolderChange() }
                        }
                    )
                    .toolbar(.hidden, for: .tabBar)

                case .smartOrganization:
                    SmartOrganizationView(
                        videoRepository: videoRepository,
                        folderRepository: folderRepository,
                        suggestionPipeline: suggestionPipeline,
                        libraryChanged: {
                            Task { await viewModel.applyFolderChange() }
                            libraryChanged()
                        }
                    )
                }
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $showsNewFolder) {
                NewFolderSheet(viewModel: viewModel)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Folders")
                .font(CentraliaTheme.Typography.display)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button("New Folder") {
                showsNewFolder = true
            }
            .font(.headline)
            .frame(minHeight: 44)
            .buttonStyle(CentraliaPressStyle())
            .accessibilityIdentifier("newFolderButton")
        }
    }

    private var folderSearchField: some View {
        HStack(spacing: CentraliaTheme.Spacing.medium) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .accessibilityHidden(true)

            TextField("Search folders", text: $viewModel.query)
                .font(.body)
                .focused($searchIsFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("foldersSearchField")

            if !viewModel.query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    viewModel.query = ""
                    searchIsFocused = true
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(Color.centraliaSecondaryText)
                .accessibilityIdentifier("clearFoldersSearch")
            }
        }
        .foregroundStyle(Color.centraliaInk)
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
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading folders…")
                .frame(maxWidth: .infinity, minHeight: 320)

        case let .failed(message):
            ContentUnavailableView {
                Label("Folders unavailable", systemImage: "exclamationmark.triangle")
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
            if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                unorganizedCollection
            }

            if viewModel.filteredFolders.isEmpty {
                if viewModel.folders.isEmpty {
                    ContentUnavailableView {
                        Label("Create your first folder", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Use folders to keep your saved shorts together.")
                    } actions: {
                        Button("New Folder") { showsNewFolder = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.centraliaInk)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ContentUnavailableView.search(text: viewModel.query)
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            } else {
                folderGrid
            }
        }
    }

    private var unorganizedCollection: some View {
        Button {
            path.append(.smartOrganization)
        } label: {
            HStack(spacing: CentraliaTheme.Spacing.medium) {
                Image(systemName: "sparkle")
                    .font(.title2.weight(.medium))
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Unorganized")
                        .font(.title2.weight(.bold))
                    Text(unorganizedDescription)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.74))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .padding(CentraliaTheme.Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(Color.centraliaInk, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(CentraliaPressStyle())
        .accessibilityLabel("Unorganized, (unorganizedDescription)")
        .accessibilityHint("Opens Smart Organization")
        .accessibilityIdentifier("unorganizedCollection")
    }

    private var unorganizedDescription: String {
        let count = viewModel.unorganizedCount
        return count == 1 ? "1 short waiting for you" : "\(count) shorts waiting for you"
    }

    private var folderGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: CentraliaTheme.Spacing.medium),
                GridItem(.flexible(), spacing: CentraliaTheme.Spacing.medium)
            ],
            spacing: CentraliaTheme.Spacing.medium
        ) {
            ForEach(viewModel.filteredFolders) { folder in
                FolderGridCard(
                    folder: folder,
                    itemCount: viewModel.itemCount(in: folder)
                ) {
                    path.append(.folder(folder))
                }
            }
        }
        .accessibilityIdentifier("folderGrid")
    }
}

private struct FolderGridCard: View {
    let folder: LibraryFolder
    let itemCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
                Image(systemName: folder.symbolName)
                    .font(.title2.weight(.medium))
                    .frame(width: 36, height: 36, alignment: .leading)
                    .accessibilityHidden(true)

                Spacer(minLength: CentraliaTheme.Spacing.small)

                Text(folder.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(itemCount) \(itemCount == 1 ? "short" : "shorts")")
                    .font(.subheadline)
                    .foregroundStyle(Color.centraliaSecondaryText)
            }
            .foregroundStyle(Color.centraliaInk)
            .padding(CentraliaTheme.Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.centraliaDivider, lineWidth: 1)
            }
        }
        .buttonStyle(CentraliaPressStyle())
        .accessibilityLabel("\(folder.name), \(itemCount) \(itemCount == 1 ? "short" : "shorts")")
    }
}

private struct NewFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: FoldersViewModel
    @State private var folderName = ""
    @State private var selectedSymbol = FolderSymbol.folder
    @FocusState private var folderNameIsFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
                    Text("Choose a clear name for this collection of saved shorts.")
                        .font(.body)
                        .foregroundStyle(Color.centraliaSecondaryText)

                    TextField("Folder name", text: $folderName)
                        .font(.body)
                        .focused($folderNameIsFocused)
                        .submitLabel(.done)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, CentraliaTheme.Spacing.medium)
                        .frame(minHeight: 56)
                        .background(
                            Color.centraliaSurface,
                            in: RoundedRectangle(cornerRadius: 16)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.centraliaDivider, lineWidth: 1)
                        }
                        .onSubmit(save)
                        .accessibilityIdentifier("newFolderNameField")

                    Text("Icon")
                        .font(.headline)
                        .padding(.top, CentraliaTheme.Spacing.small)

                    FolderSymbolPicker(selection: $selectedSymbol)

                    if let message = viewModel.failureMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(message)")
                    }
                }
                .padding(CentraliaTheme.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveNewFolderButton")
                }
            }
            .onAppear {
                folderNameIsFocused = true
            }
            .onDisappear {
                viewModel.dismissFailure()
            }
        }
        .presentationDetents([.height(500), .large])
    }

    private func save() {
        Task {
            guard await viewModel.createFolder(
                named: folderName,
                symbol: selectedSymbol
            ) != nil else { return }
            dismiss()
        }
    }
}
