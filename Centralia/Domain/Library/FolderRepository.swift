protocol FolderRepository {
    func folders() async throws -> [LibraryFolder]
}
