//
//  CentraliaApp.swift
//  Centralia
//
//  Created by David Caro on 16/09/26.
//

import SwiftUI

@main
struct CentraliaApp: App {
    @State private var container = DependencyContainer.live()

    init() {
        // Context-aware playback: start reading the network before the first play.
        NetworkContextMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
        }
    }
}
