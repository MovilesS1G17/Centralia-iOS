import SwiftUI
import UIKit

/// Renders a remote cover while preserving the card colour if it is loading,
/// unavailable, or absent. Covers come from `CoverImageLoader` (memory + disk
/// cache), so they still show offline once seen.
struct VideoCoverImage: View {
    let url: URL?

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            // Sprint 3: memory → disk → network, decoded off the main thread.
            .task(id: url) {
                guard let url else {
                    image = nil
                    return
                }
                image = CoverImageLoader.shared.cachedImage(for: url)
                if image == nil {
                    image = await CoverImageLoader.shared.image(for: url)
                }
            }
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
