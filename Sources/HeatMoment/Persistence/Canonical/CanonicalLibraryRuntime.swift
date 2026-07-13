import Foundation

struct CanonicalStoreDescriptor: Sendable, Equatable {
    let rootDirectory: URL
    let databaseURL: URL
    let assetDirectoryURL: URL
    let recoveryPointDirectoryURL: URL

    init(
        rootDirectory: URL,
        databaseFileName: String = "HeatMomentCanonical.sqlite"
    ) {
        self.rootDirectory = rootDirectory
        databaseURL = rootDirectory.appendingPathComponent(databaseFileName)
        assetDirectoryURL = rootDirectory.appendingPathComponent("Assets", isDirectory: true)
        recoveryPointDirectoryURL = rootDirectory.appendingPathComponent(
            "RecoveryPoints",
            isDirectory: true
        )
    }

    var pendingRestoreDirectory: URL {
        rootDirectory.appendingPathComponent("PendingRestore", isDirectory: true)
    }

    func storePayloadURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter(isStorePayloadURL)
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func isStorePayloadURL(_ url: URL) -> Bool {
        let databaseFileName = databaseURL.lastPathComponent
        let name = url.lastPathComponent
        return name == databaseFileName
            || name == "\(databaseFileName)-wal"
            || name == "\(databaseFileName)-shm"
    }
}

struct CanonicalLibraryRuntime: Sendable {
    let descriptor: CanonicalStoreDescriptor?
    let store: CanonicalStore
    let assetStore: FileAssetStore
    let repository: CanonicalLibraryRepository
    let assetPinStore: CanonicalAssetPinStore
    let recoveryPointStore: CanonicalRecoveryPointStore
    let recoveryPointSnapshotService: CanonicalRecoveryPointSnapshotService
    let assetReachabilityService: CanonicalAssetReachabilityService
    let assetOperationGate: CanonicalAssetOperationGate

    init(descriptor: CanonicalStoreDescriptor) throws {
        try FileManager.default.createDirectory(
            at: descriptor.rootDirectory,
            withIntermediateDirectories: true
        )
        self.descriptor = descriptor
        store = try CanonicalStore(path: descriptor.databaseURL.path)
        assetStore = FileAssetStore(rootDirectory: descriptor.assetDirectoryURL)
        assetOperationGate = CanonicalAssetOperationGate.shared(
            forAssetRootDirectory: assetStore.rootDirectory
        )
        repository = CanonicalLibraryRepository(
            store: store,
            assetStore: assetStore,
            operationGate: assetOperationGate
        )
        assetPinStore = CanonicalAssetPinStore(store: store)
        let recoveryPointStore = CanonicalRecoveryPointStore(store: store)
        self.recoveryPointStore = recoveryPointStore
        recoveryPointSnapshotService = CanonicalRecoveryPointSnapshotService(
            store: store,
            recoveryPointStore: recoveryPointStore,
            assetStore: assetStore,
            operationGate: assetOperationGate,
            rootDirectory: descriptor.rootDirectory,
            recoveryPointDirectoryURL: descriptor.recoveryPointDirectoryURL
        )
        assetReachabilityService = CanonicalAssetReachabilityService(
            store: store,
            assetStore: assetStore,
            operationGate: assetOperationGate
        )
        _ = try recoveryPointSnapshotService.reconcileRecoveryPointDirectories()
    }

    private init(store: CanonicalStore, assetStore: FileAssetStore) {
        descriptor = nil
        self.store = store
        self.assetStore = assetStore
        let rootDirectory = assetStore.rootDirectory.deletingLastPathComponent()
        assetOperationGate = CanonicalAssetOperationGate.shared(
            forAssetRootDirectory: assetStore.rootDirectory
        )
        repository = CanonicalLibraryRepository(
            store: store,
            assetStore: assetStore,
            operationGate: assetOperationGate
        )
        assetPinStore = CanonicalAssetPinStore(store: store)
        let recoveryPointStore = CanonicalRecoveryPointStore(store: store)
        self.recoveryPointStore = recoveryPointStore
        recoveryPointSnapshotService = CanonicalRecoveryPointSnapshotService(
            store: store,
            recoveryPointStore: recoveryPointStore,
            assetStore: assetStore,
            operationGate: assetOperationGate,
            rootDirectory: rootDirectory,
            recoveryPointDirectoryURL: rootDirectory.appendingPathComponent(
                "RecoveryPoints",
                isDirectory: true
            )
        )
        assetReachabilityService = CanonicalAssetReachabilityService(
            store: store,
            assetStore: assetStore,
            operationGate: assetOperationGate
        )
    }

    static var productionDescriptor: CanonicalStoreDescriptor {
        CanonicalStoreDescriptor(rootDirectory: applicationSupportDirectory)
    }

    static func makeProduction() throws -> CanonicalLibraryRuntime {
        try CanonicalLibraryRuntime(descriptor: productionDescriptor)
    }

    static func resetStorage(descriptor: CanonicalStoreDescriptor) throws {
        guard FileManager.default.fileExists(atPath: descriptor.rootDirectory.path) else {
            return
        }
        try FileManager.default.removeItem(at: descriptor.rootDirectory)
    }

    static func makeInMemoryForTests(
        assetDirectoryURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "HeatMomentCanonicalAssets-\(UUID().uuidString)", isDirectory: true)
    ) throws -> CanonicalLibraryRuntime {
        try CanonicalLibraryRuntime(
            store: CanonicalStore.makeInMemory(),
            assetStore: FileAssetStore(rootDirectory: assetDirectoryURL)
        )
    }

    private static var applicationSupportDirectory: URL {
        #if DEBUG
            if let directory = UITestSupport.localBackupApplicationSupportDirectory {
                return
                    directory
                    .appendingPathComponent("Canonical", isDirectory: true)
            }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Canonical", isDirectory: true)
    }
}
