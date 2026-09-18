import Foundation

actor MockDataStore {
    enum StoreError: LocalizedError {
        case applicationSupportUnavailable
        case unableToCreateDirectory(Error)
        case unableToRead(Error)
        case unableToDecode(Error)
        case unableToEncode(Error)
        case unableToWrite(Error)

        var errorDescription: String? {
            switch self {
            case .applicationSupportUnavailable:
                "The app's local storage directory is unavailable."
            case let .unableToCreateDirectory(error):
                "Centralia could not prepare local storage: \(error.localizedDescription)"
            case let .unableToRead(error):
                "Centralia could not read the local library: \(error.localizedDescription)"
            case let .unableToDecode(error):
                "Centralia could not understand the local library: \(error.localizedDescription)"
            case let .unableToEncode(error):
                "Centralia could not prepare the library for saving: \(error.localizedDescription)"
            case let .unableToWrite(error):
                "Centralia could not save the local library: \(error.localizedDescription)"
            }
        }
    }

    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        if let directoryURL {
            self.directoryURL = directoryURL
        } else if let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            self.directoryURL = applicationSupportURL
                .appendingPathComponent("Centralia", isDirectory: true)
                .appendingPathComponent("MockData", isDirectory: true)
        } else {
            self.directoryURL = fileManager.temporaryDirectory
                .appendingPathComponent("Centralia-Fallback", isDirectory: true)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load<Value: Codable & Sendable>(
        _ type: Value.Type,
        from filename: String,
        seed: @autoclosure () -> Value
    ) throws -> Value {
        try prepareDirectory()
        let fileURL = directoryURL.appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            let initialValue = seed()
            try save(initialValue, to: filename)
            return initialValue
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw StoreError.unableToRead(error)
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw StoreError.unableToDecode(error)
        }
    }

    func save<Value: Codable & Sendable>(_ value: Value, to filename: String) throws {
        try prepareDirectory()
        let data: Data

        do {
            data = try encoder.encode(value)
        } catch {
            throw StoreError.unableToEncode(error)
        }

        do {
            try data.write(
                to: directoryURL.appendingPathComponent(filename),
                options: .atomic
            )
        } catch {
            throw StoreError.unableToWrite(error)
        }
    }

#if DEBUG
    func reset() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
    }
#endif

    private func prepareDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw StoreError.unableToCreateDirectory(error)
        }
    }
}
