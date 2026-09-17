//
//  CentraliaApp.swift
//  Centralia
//
//  Created by David Caro on 16/09/26.
//

import SwiftUI

@main
struct CentraliaApp: App {
    @State private var container = DependencyContainer.mock()

    var body: some Scene {
        WindowGroup {
            ContentView(container: container)
        }
    }
}
