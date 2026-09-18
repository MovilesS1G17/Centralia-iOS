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

    private(set) var analysisState: AnalysisState = .idle
    private(set) var metadata: ImportedVideoMetadata?
    private(set) var suggestedTags: [String] = []
    private(set) var suggestedFolderName: String?
    private(set) var folders: [LibraryFolder] = []
    private(set) var isSaving = false
    private(set) var saveFailureMessage: String?
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
        folderRepository: any FolderRepository
    ) {
        self.pipeline = pipeline
        self.videoRepository = videoRepository
        self.folderRepository = folderRepository
    }

    func loadFolders() async {
        do {
            folders = try await folderRepository.folders()
        } catch {
            folderFailureMessage = error.localizedDescription
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

            analysisState = .processing(.generatingTags)
            let generatedTags = try await pipeline.generateTags(for: extractedMetadata)
            try ensureCurrent(source)
            suggestedTags = generatedTags

            analysisState = .processing(.suggestingFolder)
            let folderName = try await pipeline.suggestFolder(
                for: extractedMetadata,
                tags: generatedTags
            )
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
            analysisState = .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func createFolder(named name: String) async -> LibraryFolder? {
        folderFailureMessage = nil

        do {
            let folder = try await folderRepository.createFolder(named: name)
            folders.append(folder)
            folders.sort {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            selectedFolderID = folder.id
            return folder
        } catch {
            folderFailureMessage = error.localizedDescription
            return nil
        }
    }

    func addTag(_ value: String) {
        let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty,
              !selectedTags.contains(where: {
                  $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
              }) else {
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
            tags: selectedTags,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            savedAt: Date(),
            analysisStatus: .completed
        )

        do {
            try await videoRepository.saveVideo(video)
            return video
        } catch {
            saveFailureMessage = error.localizedDescription
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
