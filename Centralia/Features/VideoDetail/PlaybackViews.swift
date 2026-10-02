import AVKit
import Combine
import SwiftUI
import WebKit

/// Plays the signed MP4 stream. A URL the playback policy rejects, or an item
/// that cannot be loaded or played, calls `failed` so the caller can fall back
/// to the platform's web player.
struct StreamPlayerView: View {
    let url: URL
    let failed: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                Color.black
            }
        }
        .task {
            guard PlaybackURLPolicy.isAllowed(url) else {
                failed()
                return
            }
            // Created once: the view struct is rebuilt often, the state is kept.
            let current = player ?? AVPlayer(url: url)
            player = current
            await watch(current)
        }
        .accessibilityLabel("Video player")
    }

    private func watch(_ player: AVPlayer) async {
        guard let item = player.currentItem else {
            failed()
            return
        }
        for await status in item.publisher(for: \.status).values {
            switch status {
            case .failed:
                failed()
                return
            case .readyToPlay:
                return
            default:
                continue
            }
        }
    }
}

/// The platform's embeddable player. Only the embed's own host can be
/// navigated to: any other link is blocked. A URL the playback policy rejects,
/// or a page that fails to load, calls `failed`.
struct EmbedPlayerView: UIViewRepresentable {
    let url: URL
    let failed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, failed: failed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false
        view.backgroundColor = .clear

        if PlaybackURLPolicy.isAllowed(url) {
            view.load(URLRequest(url: url))
        } else {
            let failed = failed
            DispatchQueue.main.async { failed() }
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let embedHost: String?
        private let failed: () -> Void

        init(url: URL, failed: @escaping () -> Void) {
            embedHost = url.host?.lowercased()
            self.failed = failed
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(allows(navigationAction) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportIfFatal(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            reportIfFatal(error)
        }

        private func allows(_ action: WKNavigationAction) -> Bool {
            guard let url = action.request.url else { return false }

            // Frames inside the embed page may load their own https content;
            // everything that leaves the page (main frame, new windows) must
            // stay on the embed's host.
            if let target = action.targetFrame, !target.isMainFrame {
                return url.scheme?.lowercased() == "about" || PlaybackURLPolicy.isAllowed(url)
            }
            guard PlaybackURLPolicy.isAllowed(url) else { return false }
            return url.host?.lowercased() == embedHost
        }

        private func reportIfFatal(_ error: Error) {
            // A cancelled load is what blocking a navigation produces.
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            failed()
        }
    }
}
