import CryptoKit
import Foundation

enum LocalBackupBootRestoreResult: Equatable {
    case none
    case restored
    case failed(LocalBackupBootRestoreFailure)

    var failure: LocalBackupBootRestoreFailure? {
        if case let .failed(failure) = self {
            return failure
        }
        return nil
    }
}

struct LocalBackupBootRestoreFailure: Error, Equatable, CustomStringConvertible {
    let underlyingDescription: String

    init(underlying: Error) {
        underlyingDescription = String(describing: underlying)
    }

    var description: String {
        "本地备份恢复失败：\(underlyingDescription)"
    }
}

enum LocalBackupRestoreCriticalError: Error {
    case rollbackFailed(Error)
}

enum LocalBackupRestoreExecutor {
    private static let armedFileName = "armed"
    private static let metadataFileName = "metadata.json"
    private static let payloadDirectoryName = "payload"

    static func stageRestore(
        metadata: RecoveryPointMetadata,
        descriptor: LocalBackupStoreDescriptor
    ) throws {
        guard metadata.status == .available else {
            throw RecoveryPointError.recoveryPointUnavailable(metadata.id)
        }

        let recoveryPayloadDirectory = descriptor.recoveryDirectory
            .appendingPathComponent(metadata.id.uuidString, isDirectory: true)
            .appendingPathComponent(payloadDirectoryName, isDirectory: true)
        try validatePayload(metadata: metadata, payloadDirectory: recoveryPayloadDirectory)

        let pendingDirectory = descriptor.pendingRestoreDirectory
        try clearPendingRestore(descriptor: descriptor)
        try FileManager.default.createDirectory(
            at: pendingDirectory,
            withIntermediateDirectories: true
        )

        do {
            try FileManager.default.copyItem(
                at: recoveryPayloadDirectory,
                to: pendingDirectory.appendingPathComponent(payloadDirectoryName, isDirectory: true)
            )
            try writeMetadata(
                metadata,
                to: pendingDirectory.appendingPathComponent(metadataFileName)
            )
        } catch {
            try? clearPendingRestore(descriptor: descriptor)
            throw error
        }
    }

    static func armStagedRestore(
        metadata: RecoveryPointMetadata,
        descriptor: LocalBackupStoreDescriptor
    ) throws {
        let pendingDirectory = descriptor.pendingRestoreDirectory
        let payloadDirectory = pendingDirectory.appendingPathComponent(
            payloadDirectoryName,
            isDirectory: true
        )
        try validatePayload(metadata: metadata, payloadDirectory: payloadDirectory)
        try Data(metadata.id.uuidString.utf8).write(
            to: pendingDirectory.appendingPathComponent(armedFileName),
            options: [.atomic]
        )
    }

    static func clearPendingRestore(descriptor: LocalBackupStoreDescriptor) throws {
        try removeDirectoryIfExists(descriptor.pendingRestoreDirectory)
    }

    static func performPendingRestoreIfNeeded(
        descriptor: LocalBackupStoreDescriptor
    ) throws -> LocalBackupBootRestoreResult {
        let pendingDirectory = descriptor.pendingRestoreDirectory
        guard FileManager.default.fileExists(atPath: pendingDirectory.path) else {
            return .none
        }
        let armedURL = pendingDirectory.appendingPathComponent(armedFileName)
        guard FileManager.default.fileExists(atPath: armedURL.path) else {
            try? FileManager.default.removeItem(at: pendingDirectory)
            return .none
        }

        do {
            let metadata = try readMetadata(
                from: pendingDirectory.appendingPathComponent(metadataFileName)
            )
            let payloadDirectory = pendingDirectory.appendingPathComponent(
                payloadDirectoryName,
                isDirectory: true
            )
            try validatePayload(metadata: metadata, payloadDirectory: payloadDirectory)
            try replaceStorePayload(from: payloadDirectory, descriptor: descriptor)
            try FileManager.default.removeItem(at: pendingDirectory)
            return .restored
        } catch let error as LocalBackupRestoreCriticalError {
            throw error
        } catch {
            try? clearPendingRestore(descriptor: descriptor)
            return .failed(LocalBackupBootRestoreFailure(underlying: error))
        }
    }
}

private extension LocalBackupRestoreExecutor {
    static func replaceStorePayload(
        from payloadDirectory: URL,
        descriptor: LocalBackupStoreDescriptor
    ) throws {
        try FileManager.default.createDirectory(
            at: descriptor.rootDirectory,
            withIntermediateDirectories: true
        )
        let rollbackDirectory = descriptor.rootDirectory.appendingPathComponent(
            "RestoreRollback-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rollbackDirectory,
            withIntermediateDirectories: true
        )

        var movedCurrentPayload: [URL] = []
        var didMoveAllCurrentPayload = false
        do {
            movedCurrentPayload = try moveCurrentPayload(
                to: rollbackDirectory,
                descriptor: descriptor
            )
            didMoveAllCurrentPayload = true
            try copyIncomingPayload(from: payloadDirectory, descriptor: descriptor)
            try FileManager.default.removeItem(at: rollbackDirectory)
        } catch {
            do {
                try rollbackStorePayload(
                    movedCurrentPayload: movedCurrentPayload,
                    rollbackDirectory: rollbackDirectory,
                    removesRootPayloadBeforeRollback: didMoveAllCurrentPayload,
                    descriptor: descriptor
                )
            } catch {
                throw LocalBackupRestoreCriticalError.rollbackFailed(error)
            }
            throw error
        }
    }

    static func moveCurrentPayload(
        to rollbackDirectory: URL,
        descriptor: LocalBackupStoreDescriptor
    ) throws -> [URL] {
        var movedCurrentPayload: [URL] = []
        for url in try descriptor.storePayloadURLs() {
            let rollbackURL = rollbackDirectory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: rollbackURL)
            movedCurrentPayload.append(rollbackURL)
        }
        return movedCurrentPayload
    }

    static func copyIncomingPayload(
        from payloadDirectory: URL,
        descriptor: LocalBackupStoreDescriptor
    ) throws {
        let incomingTopLevelURLs = try FileManager.default.contentsOfDirectory(
            at: payloadDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for url in incomingTopLevelURLs.sorted(by: {
            $0.lastPathComponent < $1.lastPathComponent
        }) {
            guard descriptor.isStorePayloadURL(url) else { continue }
            let destination = descriptor.rootDirectory.appendingPathComponent(
                url.lastPathComponent,
                isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                    == true
            )
            try FileManager.default.copyItem(at: url, to: destination)
        }
    }

    static func rollbackStorePayload(
        movedCurrentPayload: [URL],
        rollbackDirectory: URL,
        removesRootPayloadBeforeRollback: Bool,
        descriptor: LocalBackupStoreDescriptor
    ) throws {
        if removesRootPayloadBeforeRollback {
            for url in try descriptor.storePayloadURLs() {
                try? FileManager.default.removeItem(at: url)
            }
        }
        for rollbackURL in movedCurrentPayload {
            let originalURL = descriptor.rootDirectory.appendingPathComponent(
                rollbackURL.lastPathComponent
            )
            if FileManager.default.fileExists(atPath: originalURL.path) {
                try? FileManager.default.removeItem(at: originalURL)
            }
            try FileManager.default.moveItem(at: rollbackURL, to: originalURL)
        }
        try? FileManager.default.removeItem(at: rollbackDirectory)
    }

    static func removeDirectoryIfExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func validatePayload(
        metadata: RecoveryPointMetadata,
        payloadDirectory: URL
    ) throws {
        guard FileManager.default.fileExists(atPath: payloadDirectory.path) else {
            throw RecoveryPointError.pendingRestoreMissingPayload
        }
        let expectedFiles = Set(metadata.files.map(\.relativePath))
        let actualFiles = try payloadRelativeFilePaths(in: payloadDirectory)
        guard expectedFiles == actualFiles else {
            throw RecoveryPointError.recoveryPointUnavailable(metadata.id)
        }

        for manifest in metadata.files {
            let fileURL = payloadDirectory.appendingPathComponent(manifest.relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw RecoveryPointError.recoveryPointUnavailable(metadata.id)
            }
            guard try fileSize(fileURL) == manifest.sizeBytes else {
                throw RecoveryPointError.recoveryPointUnavailable(metadata.id)
            }
            guard try sha256(fileURL) == manifest.sha256 else {
                throw RecoveryPointError.recoveryPointUnavailable(metadata.id)
            }
        }
    }

    static func payloadRelativeFilePaths(in payloadDirectory: URL) throws -> Set<String> {
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

    static func readMetadata(from url: URL) throws -> RecoveryPointMetadata {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecoveryPointMetadata.self, from: data)
    }

    static func writeMetadata(_ metadata: RecoveryPointMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: url, options: [.atomic])
    }

    static func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024)
            guard let data, !data.isEmpty else { break }
            data.withUnsafeBytes { buffer in
                hasher.update(bufferPointer: buffer)
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
