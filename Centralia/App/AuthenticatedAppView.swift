import SwiftUI

struct AuthenticatedAppView: View {
    let user: AuthenticatedUser
    let videoRepository: any VideoItemRepository
    let folderRepository: any FolderRepository

    @State private var selectedTab: AppTab = .library
    @State private var previousTab: AppTab = .library
    @State private var presentsSave = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "house", value: AppTab.library) {
                LibraryView(
                    videoRepository: videoRepository,
                    folderRepository: folderRepository,
                    selectedTab: $selectedTab,
                    presentSave: { presentsSave = true }
                )
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                NavigationStack {
                    UpcomingFeatureView(
                        title: "Search",
                        screenNumber: 4,
                        systemImage: "magnifyingglass",
                        detail: "Global Search is the next numbered screen."
                    )
                }
            }

            Tab("Save", systemImage: "plus", value: AppTab.save) {
                Color.clear
            }

            Tab("Folders", systemImage: "folder", value: AppTab.folders) {
                NavigationStack {
                    UpcomingFeatureView(
                        title: "Folders",
                        screenNumber: 8,
                        systemImage: "folder"
                    )
                }
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
            NavigationStack {
                UpcomingFeatureView(
                    title: "Save Short Video",
                    screenNumber: 5,
                    systemImage: "plus.square.on.square"
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") {
                            presentsSave = false
                        }
                    }
                }
            }
        }
    }
}
