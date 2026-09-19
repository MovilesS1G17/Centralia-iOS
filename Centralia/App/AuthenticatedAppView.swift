import SwiftUI

struct AuthenticatedAppView: View {
    let user: AuthenticatedUser
    let videoRepository: any VideoItemRepository
    let folderRepository: any FolderRepository
    let searchHistoryRepository: any SearchHistoryRepository
    let videoImportPipeline: any VideoImportPipeline

    @State private var selectedTab: AppTab = .library
    @State private var previousTab: AppTab = .library
    @State private var presentsSave = false
    @State private var libraryRevision = 0

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
                    folderRepository: folderRepository
                )
                .id(libraryRevision)
            }

            Tab("Profile", systemImage: "person", value: AppTab.profile) {
                NavigationStack {
                    UpcomingFeatureView(
                        title: "Profile",
                        screenNumber: 11,
                        systemImage: "person",
                        detail: "Signed in as \(user.displayName). Screen 11 will add account controls."
                    )
                }
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
            }
        }
    }
}
