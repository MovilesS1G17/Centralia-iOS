import Foundation

protocol LibraryExportService {
    func exportLibrary(for profile: UserProfile) async throws -> URL
}

enum LibraryExportError: LocalizedError {
    case unableToEncode(Error)
    case unableToWrite(Error)

    var errorDescription: String? {
        switch self {
        case let .unableToEncode(error):
            "Centralia could not prepare your export: \(error.localizedDescription)"
        case let .unableToWrite(error):
            "Centralia could not save your export: \(error.localizedDescription)"
        }
    }
}
