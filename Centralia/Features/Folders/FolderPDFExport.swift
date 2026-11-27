import Observation
import PDFKit
import SwiftUI

@Observable
final class FolderPDFExport {
    enum State {
        case idle
        case rendering(FolderPDFRenderer.Progress?)
        case ready(FolderPDFFile)
        case failed
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    var isRendering: Bool {
        if case .rendering = state { return true }
        return false
    }

    func start(folder: LibraryFolder, videos: [VideoItem]) {
        guard task == nil, !videos.isEmpty else { return }
        let shorts = videos.map { video in
            FolderPDFRenderer.Short(
                title: video.displayTitle,
                creator: video.creatorDisplayName,
                platform: video.platform.displayName,
                savedAt: video.savedAt,
                sourceURL: video.sourceURL,
                coverURL: video.coverURL
            )
        }
        state = .rendering(nil)
        task = Task(priority: .userInitiated) { [weak self] in
            do {
                let file = try await FolderPDFRenderer.render(
                    folderName: folder.name,
                    shorts: shorts,
                    cachedCover: Self.cachedCover,
                    onProgress: { [weak self] progress in
                        guard !Task.isCancelled else { return }
                        self?.state = .rendering(progress)
                    }
                )
                try Task.checkCancellation()
                self?.state = .ready(file)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed
            }
            self?.task = nil
        }
    }

    func dismiss() {
        task?.cancel()
        task = nil
        state = .idle
    }

    deinit {
        task?.cancel()
    }

    @concurrent
    private static func cachedCover(for url: URL) async -> FolderPDFRenderer.Cover? {
        let loader = await CoverImageLoader.shared
        if let data = loader.cachedResponseData(for: url) {
            return .encoded(data)
        }
        return await MainActor.run {
            loader.cachedImage(for: url)?.cgImage.map(FolderPDFRenderer.Cover.decoded)
        }
    }
}

struct FolderPDFExportStatus: View {
    let state: FolderPDFExport.State
    let preview: (FolderPDFFile) -> Void
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .rendering(progress):
            panel(title: "Preparing folder PDF", icon: "doc.richtext") {
                if let progress {
                    ProgressView(value: Double(progress.completedPages), total: Double(progress.totalPages)) {
                        Text("\(progress.completedPages) of \(progress.totalPages) pages")
                            .font(.caption)
                            .foregroundStyle(Color.centraliaSecondaryText)
                    }
                    .tint(.centraliaInk)
                } else {
                    ProgressView()
                        .accessibilityLabel("Preparing folder PDF")
                }
                Button(role: .cancel, action: dismiss) {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CentraliaPressStyle())
            }
        case let .ready(file):
            panel(title: "Folder PDF ready", icon: "checkmark.circle", dismissLabel: "Dismiss PDF export") {
                Button("Preview PDF", systemImage: "doc.richtext") { preview(file) }
                    .buttonStyle(CentraliaProminentButtonStyle())
                    .accessibilityIdentifier("folderPDFPreview")
            }
        case .failed:
            panel(title: "Couldn’t create the PDF", icon: "exclamationmark.circle", dismissLabel: "Dismiss PDF export error") {
                Button("Try Again", action: retry)
                    .buttonStyle(CentraliaProminentButtonStyle())
            }
        }
    }

    private func panel<Content: View>(
        title: LocalizedStringKey, icon: String, dismissLabel: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.small) {
            HStack(spacing: CentraliaTheme.Spacing.small) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if let dismissLabel {
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .foregroundStyle(Color.centraliaSecondaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(dismissLabel)
                    .buttonStyle(CentraliaPressStyle())
                }
            }
            content()
        }
        .padding(CentraliaTheme.Spacing.medium)
        .frame(maxWidth: 668, alignment: .leading)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.centraliaDivider, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, CentraliaTheme.Spacing.medium)
        .padding(.bottom, CentraliaTheme.Spacing.small)
        .background(Color.centraliaCanvas)
        .accessibilityElement(children: .contain)
    }
}

struct FolderPDFPreview: View {
    @Environment(\.dismiss) private var dismiss
    let file: FolderPDFFile

    var body: some View {
        NavigationStack {
            PDFContent(url: file.url)
                .background(Color.centraliaCanvas)
                .navigationTitle("Folder PDF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: file.url) {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("folderPDFShare")
                    }
                }
        }
    }

    private struct PDFContent: UIViewRepresentable {
        let url: URL

        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.backgroundColor = .clear
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.autoScales = true
            view.document = PDFDocument(url: url)
            return view
        }

        func updateUIView(_ view: PDFView, context: Context) {}
    }
}
