import Foundation
import Observation

@Observable
final class SaveVideoViewModel {
    enum AnalysisState: Equatable {
        case idle
        case processing(VideoImportStage)
        case ready
        case failed(String)
    }

    private let pipeline: any VideoImportPipeline
    private let videoRepository: any VideoItemRepository
    private let folderRepository: any FolderRepository
    private let analytics: any AnalyticsTracking
    private var hasTrackedScreen = false

    private(set) var analysisState: AnalysisState = .idle
    private(set) var metadata: ImportedVideoMetadata?
    private(set) var suggestedTags: [String] = []
    private(set) var suggestedFolderName: String?
    private(set) var folders: [LibraryFolder] = []
    private(set) var isSaving = false
    private(set) var saveFailureMessage: String?
    private(set) var saveFailureIsRetryable = false
    private(set) var lastSaveWasOrganized = false
    private(set) var folderFailureMessage: String?
    private(set) var folderSelectionError: String?

    var urlText = ""
    var selectedFolderID: UUID? {
        didSet {
            if selectedFolderID != nil {
                folderSelectionError = nil
            }
        }
    }
    var selectedTags: [String] = []
    var note = ""

    var canSave: Bool {
        analysisState == .ready && metadata != nil && !isSaving
    }

    var isDraftDirty: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedFolderID != nil
            || !selectedTags.isEmpty
            || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedFolderName: String? {
        guard let selectedFolderID else { return nil }
        return folders.first { $0.id == selectedFolderID }?.name
    }

    /// The single-tap smart-folder choice to show after import analysis.
    var smartFolderSuggestion: SmartFolderSuggestion? {
        guard analysisState == .ready else { return nil }
        return SmartFolderSuggestion.make(
            suggestedFolderName: suggestedFolderName,
            folders: folders,
            selectedFolderID: selectedFolderID
        )
    }

    var availableTagSuggestions: [String] {
        suggestedTags.filter { suggestion in
            !selectedTags.contains {
                $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame
            }
        }
    }

    init(
        pipeline: any VideoImportPipeline,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        analytics: any AnalyticsTracking = NoOpAnalyticsTracking()
    ) {
        self.pipeline = pipeline
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
        self.analytics = analytics
    }

    func trackScreenViewed() {
        guard !hasTrackedScreen else { return }
        hasTrackedScreen = true
        analytics.track(.screenViewed(.saveVideo))
    }

    private func reportError(_ error: Error) {
        analytics.track(.errorShown(screen: .saveVideo, code: FeatureError.code(for: error)))
    }

    func loadFolders() async {
        do {
            folders = try await folderRepository.folders()
        } catch {
            folderFailureMessage = FeatureError.message(for: error)
            reportError(error)
        }
    }

    func analyzeURL(after debounce: Duration = .milliseconds(450)) async {
        let source = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !source.isEmpty else {
            resetAnalysis()
            return
        }

        do {
            if debounce > .zero {
                try await Task.sleep(for: debounce)
            }
            try Task.checkCancellation()

            guard source == urlText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }

            metadata = nil
            suggestedTags = []
            suggestedFolderName = nil
            selectedFolderID = nil
            selectedTags = []

            guard let sourceURL = URL(string: source) else {
                throw VideoImportError.invalidURL
            }

            analysisState = .processing(.detectingPlatform)
            let platform = try await pipeline.detectPlatform(from: sourceURL)
            try ensureCurrent(source)

            analysisState = .processing(.extractingMetadata)
            let extractedMetadata = try await pipeline.extractMetadata(
                from: sourceURL,
                platform: platform
            )
            try ensureCurrent(source)
            metadata = extractedMetadata

            // Suggestions only enrich the save: if they fail, the short can
            // still be saved without them.
            analysisState = .processing(.generatingTags)
            let generatedTags = (try? await pipeline.generateTags(for: extractedMetadata)) ?? []
            try ensureCurrent(source)
            suggestedTags = TagCatalog.normalize(generatedTags)

            analysisState = .processing(.suggestingFolder)
            let folderName = try? await pipeline.suggestFolder(for: extractedMetadata, tags: generatedTags)
            try ensureCurrent(source)
            suggestedFolderName = folderName
            selectedFolderID = folders.first {
                $0.name.localizedCaseInsensitiveCompare(folderName ?? "") == .orderedSame
            }?.id

            analysisState = .ready
        } catch is CancellationError {
            return
        } catch {
            guard source == urlText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            metadata = nil
            suggestedTags = []
            suggestedFolderName = nil
            analysisState = .failed(FeatureError.message(for: error))
            reportError(error)
        }
    }

    @discardableResult
    func createFolder(
        named name: String,
        symbol: FolderSymbol = .folder
    ) async -> LibraryFolder? {
        folderFailureMessage = nil

        do {
            let folder = try await folderRepository.createFolder(
                named: name,
                symbolName: symbol.rawValue
            )
            folders.append(folder)
            folders.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            selectedFolderID = folder.id
            return folder
        } catch {
            folderFailureMessage = FeatureError.message(for: error)
            reportError(error)
            return nil
        }
    }

    /// Selects the suggested folder, creating it with its matching symbol when needed.
    func applySmartFolderSuggestion() async {
        guard let suggestion = smartFolderSuggestion else { return }

        if let existingFolderID = suggestion.existingFolderID {
            selectedFolderID = existingFolderID
        } else {
            _ = await createFolder(named: suggestion.folderName, symbol: suggestion.symbol)
        }
    }

    func addTag(_ value: String) {
        guard let tag = TagCatalog.normalize([value]).first,
              !TagCatalog.contains(selectedTags, tag) else {
            return
        }

        selectedTags.append(tag)
    }

    func removeTag(_ tag: String) {
        selectedTags.removeAll {
            $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
        }
    }

    func save(organized: Bool) async -> VideoItem? {
        guard canSave, let metadata else { return nil }

        if organized, selectedFolderID == nil {
            folderSelectionError = "Select a folder before saving."
            return nil
        }

        folderSelectionError = nil
        lastSaveWasOrganized = organized

        isSaving = true
        saveFailureMessage = nil
        defer { isSaving = false }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let video = VideoItem(
            id: UUID(),
            sourceURL: metadata.sourceURL,
            platform: metadata.platform,
            creator: metadata.creator,
            durationSeconds: metadata.durationSeconds,
            sourceCaption: metadata.sourceCaption,
            transcript: metadata.transcript,
            extractedOnScreenText: metadata.extractedOnScreenText,
            generatedSummary: metadata.generatedSummary,
            customTitle: nil,
            folderID: organized ? selectedFolderID : nil,
            tags: TagCatalog.normalize(selectedTags),
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            savedAt: Date(),
            analysisStatus: .completed
        )

        do {
            try await videoRepository.saveVideo(video)
            return video
        } catch {
            saveFailureMessage = FeatureError.message(for: error)
            saveFailureIsRetryable = FeatureError.isRetryable(error)
            reportError(error)
            return nil
        }
    }

    func dismissSaveFailure() {
        saveFailureMessage = nil
    }

    func dismissFolderFailure() {
        folderFailureMessage = nil
    }

    private func ensureCurrent(_ source: String) throws {
        try Task.checkCancellation()
        guard source == urlText.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw CancellationError()
        }
    }

    private func resetAnalysis() {
        analysisState = .idle
        metadata = nil
        suggestedTags = []
        suggestedFolderName = nil
        selectedFolderID = nil
        selectedTags = []
        folderSelectionError = nil
    }
}
