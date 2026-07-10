import Foundation

actor RecoveryPointManager {
    static let metadataFileName = "metadata.json"
    static let payloadDirectoryName = "payload"

    let recoveryDirectory: URL
    let maxRecoveryPoints: Int

    init(recoveryDirectory: URL, maxRecoveryPoints: Int = 3) throws {
        guard maxRecoveryPoints >= 1 else {
            throw RecoveryPointError.invalidMaxRecoveryPoints(maxRecoveryPoints)
        }
        self.recoveryDirectory = recoveryDirectory
        self.maxRecoveryPoints = maxRecoveryPoints
    }

    @discardableResult
    func createRecoveryPoint(
        from source: RecoveryPointPayloadSource,
        reason: RecoveryPointReason,
        counts: RecoveryPointCounts,
        schemaVersion: Int,
        appVersion: String,
        sourceLibraryID: String? = nil,
        createdAt: Date = .now
    ) throws -> RecoveryPointMetadata {
        let id = UUID()
        let pointDirectory = directory(for: id)
        let payloadDirectory = pointDirectory.appendingPathComponent(
            Self.payloadDirectoryName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: payloadDirectory,
                withIntermediateDirectories: true
            )
            let files = try copyPayload(
                from: source,
                to: payloadDirectory
            )
            guard !files.isEmpty else {
                throw RecoveryPointError.emptySource(source.rootDirectory)
            }
            let payloadSize = files.reduce(Int64(0)) { $0 + $1.sizeBytes }
            let metadata = RecoveryPointMetadata(
                id: id,
                createdAt: createdAt,
                reason: reason,
                status: .available,
                schemaVersion: schemaVersion,
                appVersion: appVersion,
                sourceLibraryID: sourceLibraryID,
                counts: counts,
                payloadSizeBytes: payloadSize,
                files: files.sorted { $0.relativePath < $1.relativePath }
            )
            try writeMetadata(metadata, to: pointDirectory)
        } catch {
            try? FileManager.default.removeItem(at: pointDirectory)
            throw error
        }
        try pruneOverflow()
        return try readMetadata(from: pointDirectory)
    }

    @discardableResult
    func validateRecoveryPoint(id: UUID) throws -> RecoveryPointMetadata {
        let pointDirectory = directory(for: id)
        guard FileManager.default.fileExists(atPath: pointDirectory.path) else {
            throw RecoveryPointError.recoveryPointNotFound(id)
        }

        var metadata = try readMetadata(from: pointDirectory)
        let payloadDirectory = pointDirectory.appendingPathComponent(
            Self.payloadDirectoryName, isDirectory: true)
        let expectedFiles = Set(metadata.files.map(\.relativePath))
        let actualFiles = try payloadRelativeFilePaths(in: payloadDirectory)
        let manifestsAreComplete = expectedFiles == actualFiles
        let filesMatchManifest = try metadata.files.allSatisfy { manifest in
            let fileURL = payloadDirectory.appendingPathComponent(manifest.relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return false
            }
            let size = try fileSize(fileURL)
            guard size == manifest.sizeBytes else {
                return false
            }
            let digest = try sha256(fileURL)
            return digest == manifest.sha256
        }
        let isValid = manifestsAreComplete && filesMatchManifest

        let newStatus: RecoveryPointStatus = isValid ? .available : .invalid
        if metadata.status != newStatus {
            metadata.status = newStatus
            try writeMetadata(metadata, to: pointDirectory)
        }
        return metadata
    }
}
