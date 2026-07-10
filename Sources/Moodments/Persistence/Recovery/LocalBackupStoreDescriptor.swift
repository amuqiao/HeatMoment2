import Foundation

struct LocalBackupStoreDescriptor: Sendable, Equatable {
    let rootDirectory: URL
    let storeFileName: String
    let recoveryDirectoryName: String
    let sourceLibraryID: String

    init(
        rootDirectory: URL,
        storeFileName: String = "Moodments.store",
        recoveryDirectoryName: String = "RecoveryPoints",
        sourceLibraryID: String = "local"
    ) {
        self.rootDirectory = rootDirectory
        self.storeFileName = storeFileName
        self.recoveryDirectoryName = recoveryDirectoryName
        self.sourceLibraryID = sourceLibraryID
    }

    var storeURL: URL {
        rootDirectory.appendingPathComponent(storeFileName)
    }

    var recoveryDirectory: URL {
        rootDirectory.appendingPathComponent(recoveryDirectoryName, isDirectory: true)
    }

    func payloadSource() throws -> RecoveryPointPayloadSource {
        let payloadURLs = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter(isStorePayloadURL)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return RecoveryPointPayloadSource(
            rootDirectory: rootDirectory,
            includedURLs: payloadURLs
        )
    }

    private func isStorePayloadURL(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name == storeFileName
            || name.hasPrefix("\(storeFileName)-")
            || name.hasPrefix("\(storeFileName)_")
    }
}
