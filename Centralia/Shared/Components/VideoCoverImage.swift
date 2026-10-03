import SwiftUI

/// Renders a remote cover while preserving the card colour if it is loading,
/// unavailable, or absent.
struct VideoCoverImage: View {
    let url: URL?

    var body: some View {
        Color.clear
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Keeps text badges legible over a real cover image.
struct VideoCoverGradient: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.35)],
            startPoint: .center,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
