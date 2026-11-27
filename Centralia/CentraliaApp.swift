//
//  CentraliaApp.swift
//  Centralia
//
//  Created by David Caro on 16/09/26.
//

import SwiftUI

@main
struct CentraliaApp: App {
    @State private var container: DependencyContainer

    init() {
        #if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains("--ui-testing") {
            let testID = ProcessInfo.processInfo.environment["CENTRALIA_UI_TEST_DATA_ID"].flatMap(UUID.init(uuidString:)) ?? UUID()
            let directory = URL.temporaryDirectory.appending(path: testID.uuidString)
            let container = DependencyContainer.mock(
                store: MockDataStore(directoryURL: directory),
                savedSearchStore: SavedSearchStore(directory: directory.appending(path: "saved-searches")),
                folderSuggestionCache: FolderSuggestionCache(directory: directory.appending(path: "folder-suggestions")),
                includeSampleContent: !launchArguments.contains("--empty-library"),
                offlineDemoDirectory: launchArguments.contains("--folder-sync-ui-testing")
                    ? directory.appending(path: "offline") : nil,
                offline: launchArguments.contains("--offline-ui-testing")
            )
            _container = State(initialValue: container)
            return
        }
        #endif
        _container = State(initialValue: .live())

        // Context-aware playback: start reading the network before the first play.
        NetworkContextMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
        }
    }
}
