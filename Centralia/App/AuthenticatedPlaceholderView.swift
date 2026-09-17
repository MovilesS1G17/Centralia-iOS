import SwiftUI

struct AuthenticatedPlaceholderView: View {
    let user: AuthenticatedUser

    var body: some View {
        ContentUnavailableView {
            Label("Authentication complete", systemImage: "checkmark.seal.fill")
        } description: {
            Text("Signed in as \(user.displayName). Placeholder.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CentraliaTheme.Spacing.large)
        .background(Color.centraliaCanvas.ignoresSafeArea())
        .foregroundStyle(Color.centraliaInk)
    }
}
