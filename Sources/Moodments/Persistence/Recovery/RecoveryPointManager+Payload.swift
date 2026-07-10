import Foundation

extension RecoveryPointManager {
    func copyPayload(
        from source: RecoveryPointPayloadSource,
        to payloadDirectory: URL
    ) throws -> [RecoveryPointFileManifest] {
        guard !source.includedURLs.isEmpty else {
            throw RecoveryPointError.emptySource(source.rootDirectory)
        }

        var files: [RecoveryPointFileManifest] = []
        var copiedRelativePaths = Set<String>()
        for includedURL in source.includedURLs {
            try copyPayloadItem(
                includedURL,
                rootDirectory: source.rootDirectory,
                payloadDirectory: payloadDirectory,
                copiedRelativePaths: &copiedRelativePaths,
                files: &files
            )
        }
        return files
    }

    func copyPayloadItem(
        _ sourceURL: URL,
        rootDirectory: URL,
        payloadDirectory: URL,
        copiedRelativePaths: inout Set<String>,
        files: inout [RecoveryPointFileManifest]
    ) throws {
        guard sourceURL.standardizedFileURL.path != rootDirectory.standardizedFileURL.path else {
            throw RecoveryPointError.payloadSourceCannotBeRoot(rootDirectory)
        }
        guard !isInsideRecoveryDirectory(sourceURL) else {
            throw RecoveryPointError.recoveryDirectoryIncluded(sourceURL)
        }
        let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            try copyPayloadDirectory(
                sourceURL,
                rootDirectory: rootDirectory,
                payloadDirectory: payloadDirectory,
                copiedRelativePaths: &copiedRelativePaths,
                files: &files
            )
            return
        }

        try copyPayloadFile(
            sourceURL,
            rootDirectory: rootDirectory,
            payloadDirectory: payloadDirectory,
            copiedRelativePaths: &copiedRelativePaths,
            files: &files
        )
    }

    func copyPayloadDirectory(
        _ sourceDirectory: URL,
        rootDirectory: URL,
        payloadDirectory: URL,
        copiedRelativePaths: inout Set<String>,
        files: inout [RecoveryPointFileManifest]
    ) throws {
        guard
            let enumerator = FileManager.default.enumerator(
                at: sourceDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw RecoveryPointError.emptySource(sourceDirectory)
        }

        for case let sourceURL as URL in enumerator {
            if isInsideRecoveryDirectory(sourceURL) {
                throw RecoveryPointError.recoveryDirectoryIncluded(sourceURL)
            }

            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                continue
            }

            try copyPayloadFile(
                sourceURL,
                rootDirectory: rootDirectory,
                payloadDirectory: payloadDirectory,
                copiedRelativePaths: &copiedRelativePaths,
                files: &files
            )
        }
    }

    func copyPayloadFile(
        _ sourceURL: URL,
        rootDirectory: URL,
        payloadDirectory: URL,
        copiedRelativePaths: inout Set<String>,
        files: inout [RecoveryPointFileManifest]
    ) throws {
        let relativePath = try sourceURL.relativePath(from: rootDirectory)
        guard copiedRelativePaths.insert(relativePath).inserted else {
            throw RecoveryPointError.duplicatePayloadPath(relativePath)
        }

        let destinationURL = payloadDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        let size = try fileSize(destinationURL)
        let digest = try sha256(destinationURL)
        files.append(
            RecoveryPointFileManifest(
                relativePath: relativePath,
                sizeBytes: size,
                sha256: digest
            ))
    }

    func payloadRelativeFilePaths(in payloadDirectory: URL) throws -> Set<String> {
        guard
            let enumerator = FileManager.default.enumerator(
                at: payloadDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var filePaths = Set<String>()
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            filePaths.insert(try fileURL.relativePath(from: payloadDirectory))
        }
        return filePaths
    }

    func isInsideRecoveryDirectory(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let recoveryPath = recoveryDirectory.standardizedFileURL.path
        return path == recoveryPath || path.hasPrefix(recoveryPath + "/")
    }
}
