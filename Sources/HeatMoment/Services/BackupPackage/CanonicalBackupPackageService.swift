import Foundation

actor CanonicalBackupPackageService: BackupPackageServicing {
    let runtime: CanonicalLibraryRuntime
    let appVersion: String
    let exportHistoryStore: BackupPackageExportHistoryStore
    let removePreparedExportDirectory: @Sendable (URL) throws -> Void
    let enforceRecoveryPointRetention: @Sendable (CanonicalLibraryRuntime) throws -> [UUID]

    init(
        runtime: CanonicalLibraryRuntime,
        appVersion: String,
        exportHistoryStore: BackupPackageExportHistoryStore = BackupPackageExportHistoryStore(),
        removePreparedExportDirectory:
            @escaping @Sendable (URL) throws -> Void = { directory in
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
            },
        enforceRecoveryPointRetention:
            @escaping @Sendable (
                CanonicalLibraryRuntime
            ) throws -> [UUID] = { runtime in
                try runtime.recoveryPointSnapshotService.enforceRecoveryPointRetention()
            }
    ) {
        self.runtime = runtime
        self.appVersion = appVersion
        self.exportHistoryStore = exportHistoryStore
        self.removePreparedExportDirectory = removePreparedExportDirectory
        self.enforceRecoveryPointRetention = enforceRecoveryPointRetention
    }

    func currentSummary() async throws -> BackupPackageLibrarySummary {
        guard runtime.descriptor != nil else {
            throw BackupPackageError.runtimeRequiresDescriptor
        }
        let counts = try runtime.store.read { db in
            try Self.counts(in: db)
        }
        return BackupPackageLibrarySummary(
            counts: BackupRecoveryCounts(counts: counts),
            lastExportedAt: exportHistoryStore.lastExportedAt()
        )
    }

    func discardAbandonedPreparedExports() async throws {
        guard let descriptor = runtime.descriptor else {
            throw BackupPackageError.runtimeRequiresDescriptor
        }
        try discardAbandonedPreparedExports(descriptor: descriptor)
    }

    func prepareExportPackage(createdAt: Date) async throws -> BackupPackagePreparedExport {
        guard let descriptor = runtime.descriptor else {
            throw BackupPackageError.runtimeRequiresDescriptor
        }
        return try runtime.assetOperationGate.performSync {
            try prepareExportPackageWithoutGate(descriptor: descriptor, createdAt: createdAt)
        }
    }

    func completePreparedExport(
        _ preparedExport: BackupPackagePreparedExport,
        completedAt: Date
    ) async throws -> BackupPackageExportCompletion {
        try completePreparedExportWithoutGate(preparedExport, completedAt: completedAt)
    }

    func discardPreparedExport(_ preparedExport: BackupPackagePreparedExport) async throws {
        try removePreparedExportDirectoryIfExists(preparedExport.preparedDirectory)
    }

    func inspectPackage(at url: URL) async throws -> BackupPackagePreview {
        guard let descriptor = runtime.descriptor else {
            throw BackupPackageError.runtimeRequiresDescriptor
        }
        let fileManager = FileManager.default
        let sessionID = UUID()
        let sessionDirectory = importRootDirectory(descriptor: descriptor)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        let packageURL = sessionDirectory.appendingPathComponent(url.lastPathComponent)
        let extractedDirectory = sessionDirectory.appendingPathComponent("Extracted", isDirectory: true)
        if fileManager.fileExists(atPath: sessionDirectory.path) {
            try fileManager.removeItem(at: sessionDirectory)
        }
        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            try fileManager.copyItem(at: url, to: packageURL)
            let manifest = try BackupPackageArchive.extract(from: packageURL, to: extractedDirectory)
            try validateManifest(manifest)
            try BackupPackageArchive.validatePayloads(in: extractedDirectory, manifest: manifest)
            try validateExtractedPackage(manifest: manifest, extractedDirectory: extractedDirectory)
            return BackupPackagePreview(
                id: manifest.packageID,
                createdAt: manifest.createdAt,
                sourceAppVersion: manifest.sourceAppVersion,
                sourceSchemaVersion: manifest.sourceSchemaVersion,
                sourceLibraryID: manifest.sourceLibraryID,
                packageURL: packageURL,
                stagingDirectory: sessionDirectory,
                manifest: manifest,
                counts: BackupRecoveryCounts(restoreSemantics: manifest.restoreSemantics)
            )
        } catch {
            try removeDirectory(sessionDirectory, originalError: error)
        }
    }

    func prepareImport(_ preview: BackupPackagePreview, now: Date) async throws
        -> BackupPackagePreparedImport {
        guard let descriptor = runtime.descriptor else {
            throw BackupPackageError.runtimeRequiresDescriptor
        }
        return try runtime.assetOperationGate.performSync {
            try prepareImportWithoutGate(preview, descriptor: descriptor, now: now)
        }
    }
}
