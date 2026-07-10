import Foundation
import SwiftData

struct CanonicalStoreDescriptor: Sendable, Equatable {
    let rootDirectory: URL
    let databaseURL: URL

    init(
        rootDirectory: URL,
        databaseFileName: String = "MoodmentsCanonical.sqlite"
    ) {
        self.rootDirectory = rootDirectory
        databaseURL = rootDirectory.appendingPathComponent(databaseFileName)
    }
}

struct CanonicalLibraryRuntime: Sendable {
    let descriptor: CanonicalStoreDescriptor?
    let store: CanonicalStore
    let repository: CanonicalLibraryRepository

    init(descriptor: CanonicalStoreDescriptor) throws {
        try FileManager.default.createDirectory(
            at: descriptor.rootDirectory,
            withIntermediateDirectories: true
        )
        self.descriptor = descriptor
        store = try CanonicalStore(path: descriptor.databaseURL.path)
        repository = CanonicalLibraryRepository(store: store)
    }

    private init(store: CanonicalStore) {
        descriptor = nil
        self.store = store
        repository = CanonicalLibraryRepository(store: store)
    }

    static func makeProduction() throws -> CanonicalLibraryRuntime {
        try CanonicalLibraryRuntime(
            descriptor: CanonicalStoreDescriptor(rootDirectory: applicationSupportDirectory)
        )
    }

    static func makeInMemoryForTests() throws -> CanonicalLibraryRuntime {
        try CanonicalLibraryRuntime(store: CanonicalStore.makeInMemory())
    }

    @discardableResult
    func importFromSwiftDataIfNeeded(
        modelContainer: ModelContainer,
        importedAt: Date = .now
    ) async throws -> SwiftDataCanonicalImportResult {
        let importer = SwiftDataCanonicalImporter(modelContainer: modelContainer)
        return try await importer.importIfNeeded(into: store, importedAt: importedAt)
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
