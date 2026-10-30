import SwiftUI

/// Eventual connectivity (Sprint 3): tells the user they are offline and what
/// still works, and how many changes are waiting to sync. Same texts as
/// `OfflineBanner` on Android.
struct OfflineBanner: View {
    let isOnline: Bool
    let pendingChanges: Int

    var body: some View {
        if !isOnline || pendingChanges > 0 {
            Text(Self.text(isOnline: isOnline, pendingChanges: pendingChanges))
                .font(.caption)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.centraliaInk)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// Pure text rule, shared with the tests (and with Android).
    nonisolated static func text(isOnline: Bool, pendingChanges: Int) -> String {
        let changes = pendingChanges == 1 ? "1 change" : "\(pendingChanges) changes"
        if !isOnline && pendingChanges > 0 {
            return "You're offline. Showing your saved library · \(changes) will sync when you're back online."
        }
        if !isOnline {
            return "You're offline. Showing your saved library."
        }
        return "Back online · syncing \(changes)…"
    }
}
