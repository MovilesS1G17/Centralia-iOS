import SwiftUI

struct UpcomingFeatureView: View {
    let title: String
    let screenNumber: Int
    let systemImage: String
    var detail: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail ?? "Screen \(screenNumber) will be implemented in its numbered flow.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(CentraliaTheme.Spacing.large)
        .background(Color.centraliaCanvas.ignoresSafeArea())
        .foregroundStyle(Color.centraliaInk)
        .navigationTitle(title)
    }
}
