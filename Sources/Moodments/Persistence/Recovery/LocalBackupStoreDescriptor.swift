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

    var pendingRestoreDirectory: URL {
        rootDirectory.appendingPathComponent("PendingRestore", isDirectory: true)
    }

    func payloadSource() throws -> RecoveryPointPayloadSource {
        try RecoveryPointPayloadSource(
            rootDirectory: rootDirectory,
            includedURLs: storePayloadURLs()
        )
    }

    func storePayloadURLs() throws -> [URL] {
        let payloadURLs = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter(isStorePayloadURL)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return payloadURLs
    }

    func isStorePayloadURL(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name == storeFileName
            || name.hasPrefix("\(storeFileName)-")
            || name.hasPrefix("\(storeFileName)_")
    }
}
