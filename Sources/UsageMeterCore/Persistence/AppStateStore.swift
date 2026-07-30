import Darwin
import Foundation

public enum AppStateStoreError: Error, Equatable {
    case corruptData
}

public actor AppStateStore {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws -> PersistedAppState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data = try Data(contentsOf: fileURL)
        do {
            return try JSONDecoder().decode(PersistedAppState.self, from: data)
        } catch is DecodingError {
            throw AppStateStoreError.corruptData
        }
    }

    public func save(_ state: PersistedAppState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let temporaryURL = directoryURL.appending(
            path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }

        let data = try JSONEncoder().encode(state)
        try data.write(to: temporaryURL, options: .withoutOverwriting)

        let status = temporaryURL.path.withCString { sourcePath in
            fileURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard status == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
