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
            if container.session.isRestoringSession {
                ProgressView("Restoring your session…")
            } else {
                switch container.session.phase {
                case .unauthenticated(.signUp):
                    SignUpView(
                        repository: container.authenticationRepository,
                        showLogIn: container.session.showLogIn,
                        showEmailVerification: container.session.showEmailVerification,
                        completeAuthentication: container.session.completeAuthentication
                    )

                case .unauthenticated(.logIn):
                    LogInView(
                        repository: container.authenticationRepository,
                        showSignUp: container.session.showSignUp,
                        showEmailVerification: container.session.showEmailVerification,
                        completeAuthentication: container.session.completeAuthentication
                    )

                case let .unauthenticated(.emailVerification(context)):
                    EmailVerificationView(
                        repository: container.authenticationRepository,
                        context: context,
                        cancel: {
                            switch context.origin {
                            case .registration:
                                container.session.showSignUp()
                            case .signIn:
                                container.session.showLogIn()
                            }
                        },
                        completeAuthentication: container.session.completeAuthentication
                    )

                case let .authenticated(user):
                    AuthenticatedAppView(
                        user: user,
                        videoRepository: container.videoItemRepository,
                        folderRepository: container.folderRepository,
                        searchHistoryRepository: container.searchHistoryRepository,
                        userRepository: container.userRepository,
                        libraryExportService: container.libraryExportService,
                        authenticationRepository: container.authenticationRepository,
                        videoImportPipeline: container.videoImportPipeline,
                        userChanged: container.session.updateAuthenticatedUser,
                        signedOut: container.session.signOut
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: container.session.phase)
        .task {
            await container.session.restoreAuthentication(
                using: container.authenticationRepository
            )
        }
    }
}

#Preview {
    ContentView(container: .mock())
}
