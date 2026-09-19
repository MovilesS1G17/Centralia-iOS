import SwiftUI

struct AuthenticatedAppView: View {
    let user: AuthenticatedUser
    let videoRepository: any VideoItemRepository
    let folderRepository: any FolderRepository
    let searchHistoryRepository: any SearchHistoryRepository
    let userRepository: any UserRepository
    let libraryExportService: any LibraryExportService
    let authenticationRepository: any AuthenticationRepository
    let videoImportPipeline: any VideoImportPipeline
    let userChanged: (AuthenticatedUser) -> Void
    let signedOut: () -> Void

    @State private var selectedTab: AppTab = .library
    @State private var previousTab: AppTab = .library
    @State private var presentsSave = false
    @State private var libraryRevision = 0
    @State private var foldersRevision = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "house", value: AppTab.library) {
                LibraryView(
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    selectedTab: $selectedTab,
                    presentSave: { presentsSave = true }
                )
                .id(libraryRevision)
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchView(
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    searchHistoryRepository: searchHistoryRepository
                )
                .id(libraryRevision)
            }

            Tab("Save", systemImage: "plus", value: AppTab.save) {
                Color.clear
            }

            Tab("Folders", systemImage: "folder", value: AppTab.folders) {
                FoldersView(
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    suggestionPipeline: videoImportPipeline,
                    libraryChanged: {
                        libraryRevision += 1
                    }
                )
                .id(foldersRevision)
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
            }
        }
        .tint(Color.centraliaInk)
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
                folderRepository: folderRepository
            ) {
                libraryRevision += 1
                foldersRevision += 1
            }
        }
    }
}
