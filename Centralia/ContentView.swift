//
//  ContentView.swift
//  Centralia
//
//  Created by David Caro on 16/09/26.
//

import SwiftUI

struct ContentView: View {
    let container: DependencyContainer

    var body: some View {
        Group {
            switch container.session.phase {
            case .unauthenticated(.signUp):
                SignUpView(
                    repository: container.authenticationRepository,
                    showLogIn: container.session.showLogIn,
                    completeAuthentication: container.session.completeAuthentication
                )

            case .unauthenticated(.logIn):
                LogInView(
                    repository: container.authenticationRepository,
                    showSignUp: container.session.showSignUp,
                    completeAuthentication: container.session.completeAuthentication
                )

            case let .authenticated(user):
                AuthenticatedAppView(
                    user: user,
                    videoRepository: container.videoItemRepository,
                    folderRepository: container.folderRepository,
                    searchHistoryRepository: container.searchHistoryRepository
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: container.session.phase)
    }
}

#Preview {
    ContentView(container: .mock())
}
