import Foundation

extension CanonicalBackupPackageService {
    static let completedPreparedExportMarkerFileName = ".share-completed"
    static let completedPreparedExportRetentionInterval: TimeInterval = 60 * 60

    func exportRootDirectory(descriptor: CanonicalStoreDescriptor) -> URL {
        descriptor.rootDirectory.appendingPathComponent("BackupPackageExports", isDirectory: true)
    }

    func importRootDirectory(descriptor: CanonicalStoreDescriptor) -> URL {
        descriptor.rootDirectory.appendingPathComponent("BackupPackageImports", isDirectory: true)
    }

    func importStagingDirectory(
        descriptor: CanonicalStoreDescriptor,
        sessionID: UUID
    ) -> URL {
        importRootDirectory(descriptor: descriptor)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    func exportStagingDirectory(
        descriptor: CanonicalStoreDescriptor,
        packageID: UUID
    ) -> URL {
        exportRootDirectory(descriptor: descriptor)
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(packageID.uuidString, isDirectory: true)
    }

    func preparedExportRootDirectory(descriptor: CanonicalStoreDescriptor) -> URL {
        exportRootDirectory(descriptor: descriptor)
            .appendingPathComponent("Prepared", isDirectory: true)
    }

    func preparedExportDirectory(
        descriptor: CanonicalStoreDescriptor,
        packageID: UUID
    ) -> URL {
        preparedExportRootDirectory(descriptor: descriptor)
            .appendingPathComponent(packageID.uuidString, isDirectory: true)
    }

    func exportPackageURL(
        preparedDirectory: URL,
        packageID: UUID,
        createdAt: Date
    ) -> URL {
        let timestamp = Int(createdAt.timeIntervalSince1970)
        return preparedDirectory
            .appendingPathComponent(
                "HeatMoment-\(timestamp)-\(packageID.uuidString.prefix(8)).heatmomentbackup"
            )
    }

    func discardAbandonedPreparedExports(
        descriptor: CanonicalStoreDescriptor,
        now: Date = .now
    ) throws {
        let rootDirectory = preparedExportRootDirectory(descriptor: descriptor)
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return }
        let preparedDirectories = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in preparedDirectories {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }
            if try shouldRetainPreparedExportDirectory(directory, now: now) {
                continue
            }
            try removePreparedExportDirectory(directory)
        }
    }

    func markPreparedExportCompleted(
        _ preparedDirectory: URL,
        completedAt: Date
    ) throws {
        let markerURL = completedPreparedExportMarkerURL(preparedDirectory)
        let data = Data("\(completedAt.timeIntervalSince1970)".utf8)
        try data.write(to: markerURL, options: .atomic)
    }

    func completedPreparedExportMarkerURL(_ preparedDirectory: URL) -> URL {
        preparedDirectory.appendingPathComponent(Self.completedPreparedExportMarkerFileName)
    }

    func shouldRetainPreparedExportDirectory(_ directory: URL, now: Date) throws -> Bool {
        let markerURL = completedPreparedExportMarkerURL(directory)
        guard FileManager.default.fileExists(atPath: markerURL.path) else { return false }
        let markerData = try Data(contentsOf: markerURL)
        guard let rawTimestamp = String(data: markerData, encoding: .utf8),
            let completedTimestamp = TimeInterval(rawTimestamp)
        else {
            throw BackupPackageError.invalidPreparedExportCompletionMarker(markerURL.path)
        }
        let completedAt = Date(timeIntervalSince1970: completedTimestamp)
        return now.timeIntervalSince(completedAt) < Self.completedPreparedExportRetentionInterval
    }

    func discardAllImportStaging(descriptor: CanonicalStoreDescriptor) throws {
        try removeDirectoryIfExists(importRootDirectory(descriptor: descriptor))
    }

    func relativePath(for url: URL, rootDirectory: URL) throws -> String {
        let rootPath = rootDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            throw BackupPackageError.fileOutsideRoot(path)
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    func removeDirectory(_ directory: URL, originalError: Error) throws -> Never {
        do {
            try removeDirectoryIfExists(directory)
        } catch {
            throw BackupPackageError.cleanupFailed(
                originalError: String(describing: originalError),
                cleanupError: String(describing: error)
            )
        }
        throw originalError
    }

    func removeDirectoryIfExists(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func removePreparedExportDirectoryIfExists(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try removePreparedExportDirectory(directory)
        }
    }
}
