import Foundation

protocol FolderRepository {
    func folders() async throws -> [LibraryFolder]
    func createFolder(named name: String, symbolName: String) async throws -> LibraryFolder
    func renameFolder(id: UUID, to name: String) async throws -> LibraryFolder
    func deleteFolder(id: UUID) async throws
}

extension FolderRepository {
    func createFolder(named name: String) async throws -> LibraryFolder {
        try await createFolder(named: name, symbolName: FolderSymbol.folder.rawValue)
    }
}

enum FolderRepositoryError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case folderNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Enter a folder name."
        case .duplicateName:
            "A folder with that name already exists."
        case .folderNotFound:
            "This folder is no longer available."
        }
    }
}
