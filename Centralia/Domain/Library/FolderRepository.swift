import Foundation

protocol FolderRepository {
    func folders() async throws -> [LibraryFolder]
    func createFolder(named name: String) async throws -> LibraryFolder
}

enum FolderRepositoryError: LocalizedError, Equatable {
    case emptyName
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Enter a folder name."
        case .duplicateName:
            "A folder with that name already exists."
        }
    }
}
