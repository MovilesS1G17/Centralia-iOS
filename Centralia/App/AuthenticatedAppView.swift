import SwiftUI

extension EnvironmentValues {
    @Entry var offlineLibraryStatus: OfflineStatus? = nil
    @Entry var watchLaterStore: (any WatchLaterStoring)? = nil
}

struct AuthenticatedAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    let user: AuthenticatedUser
    let videoRepository: any VideoItemRepository
    let folderRepository: any FolderRepository
    var playbackRepository: (any VideoPlaybackRepository)? = nil
    var offlineStatus = OfflineStatus()
    let trends: any TrendsLoading
    let searchHistoryRepository: any SearchHistoryRepository
    let savedSearchStore: SavedSearchStore
    let folderSuggestionCache: FolderSuggestionCache
    let userRepository: any UserRepository
    let libraryExportService: any LibraryExportService
    let authenticationRepository: any AuthenticationRepository
    let videoImportPipeline: any VideoImportPipeline
    let userChanged: (AuthenticatedUser) -> Void
    let signedOut: () -> Void

    @State private var selectedTab: AppTab = .library
    @State private var previousTab: AppTab = .library
    @State private var presentsSave = false
    @State private var watchLaterStore: (any WatchLaterStoring)?
    @State private var libraryRevision = 0
    @State private var foldersRevision = 0

    var body: some View {
        VStack(spacing: 0) {
            // Sprint 3 (eventual connectivity): offline / syncing banner.
            OfflineBanner(isOnline: offlineStatus.isOnline, pendingChanges: offlineStatus.pendingChanges)
            tabs
        }
        .animation(.easeOut(duration: 0.2), value: offlineStatus.isOnline)
        .animation(.easeOut(duration: 0.2), value: offlineStatus.pendingChanges)
        .environment(\.offlineLibraryStatus, offlineStatus)
        .environment(\.watchLaterStore, watchLaterStore)
        .task(id: user.id) {
            watchLaterStore = CoreDataWatchLaterStore(accountID: user.id)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { offlineStatus.retrySync() }
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "house", value: AppTab.library) {
                LibraryView(
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    selectedTab: $selectedTab,
                    userDisplayName: user.displayName,
                    playbackRepository: playbackRepository,
                    trends: trends,
                    rediscoverDismissals: UserDefaultsRediscoverDismissals(accountID: user.id),
                    insightsStore: FileInsightsSnapshotStore(accountID: user.id),
                    presentSave: { presentsSave = true }
                )
                .id(libraryRevision)
                .centraliaTabContent()
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView(
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    searchHistoryRepository: searchHistoryRepository,
                    savedSearchStore: savedSearchStore,
                    userID: user.id,
                    playbackRepository: playbackRepository
                )
                .id(libraryRevision)
                .centraliaTabContent()
            }

            Tab("Save", systemImage: "plus", value: AppTab.save) {
                Color.clear
            }

            Tab("Folders", systemImage: "folder", value: AppTab.folders) {
                FoldersView(
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    suggestionPipeline: videoImportPipeline,
                    suggestionCache: folderSuggestionCache,
                    accountID: user.id,
                    playbackRepository: playbackRepository,
                    libraryChanged: {
                        libraryRevision += 1
                    }
                )
                .id(foldersRevision)
                .centraliaTabContent()
            }

            Tab("Profile", systemImage: "person", value: AppTab.profile) {
                ProfileView(
                    authenticatedUser: user,
                    userRepository: userRepository,
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    exportService: libraryExportService,
                    authenticationRepository: authenticationRepository,
                    userChanged: userChanged,
                    signedOut: signedOut
                )
                .id(user.id)
                .centraliaTabContent()
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            guard newValue == .save else {
                previousTab = newValue
                return
            }

            selectedTab = oldValue == .save ? previousTab : oldValue
            presentsSave = true
        }
        .sheet(isPresented: $presentsSave) {
            SaveVideoView(
                pipeline: videoImportPipeline,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                playbackRepository: playbackRepository
            ) {
                libraryRevision += 1
                foldersRevision += 1
            }
        }
    }
}

private extension View {
    func centraliaTabContent() -> some View {
        GeometryReader { proxy in
            self
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .background(Color.centraliaCanvas.ignoresSafeArea())
    }
}
