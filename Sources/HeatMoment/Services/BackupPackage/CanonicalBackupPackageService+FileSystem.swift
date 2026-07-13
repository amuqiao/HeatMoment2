import Foundation

extension CanonicalBackupPackageService {
    func exportRootDirectory(descriptor: CanonicalStoreDescriptor) -> URL {
        descriptor.rootDirectory.appendingPathComponent("BackupPackageExports", isDirectory: true)
    }

    func importRootDirectory(descriptor: CanonicalStoreDescriptor) -> URL {
        descriptor.rootDirectory.appendingPathComponent("BackupPackageImports", isDirectory: true)
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

    func discardAbandonedPreparedExports(descriptor: CanonicalStoreDescriptor) throws {
        try removePreparedExportDirectoryIfExists(
            preparedExportRootDirectory(descriptor: descriptor)
        )
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
