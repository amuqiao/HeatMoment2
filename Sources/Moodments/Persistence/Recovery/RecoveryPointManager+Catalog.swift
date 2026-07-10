import Foundation

extension RecoveryPointManager {
    func listRecoveryPoints() throws -> [RecoveryPointMetadata] {
        try recoveryPointDirectories()
            .map { readMetadataOrInvalid(from: $0) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func pruneOverflow() throws {
        let points = try listRecoveryPoints().sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .available
            }
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
        guard points.count > maxRecoveryPoints else { return }
        for point in points.dropFirst(maxRecoveryPoints) {
            try FileManager.default.removeItem(at: directory(for: point.id))
        }
    }

    func recoveryPointDirectories() throws -> [URL] {
        try FileManager.default.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )
        let pointDirectories = try FileManager.default.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return pointDirectories.filter { directory in
            guard
                (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else {
                return false
            }
            return UUID(uuidString: directory.lastPathComponent) != nil
        }
    }

    func directory(for id: UUID) -> URL {
        recoveryDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func readMetadata(from pointDirectory: URL) throws -> RecoveryPointMetadata {
        let metadataURL = pointDirectory.appendingPathComponent(Self.metadataFileName)
        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecoveryPointMetadata.self, from: data)
    }

    func readMetadataOrInvalid(from pointDirectory: URL) -> RecoveryPointMetadata {
        do {
            return try readMetadata(from: pointDirectory)
        } catch {
            let id = UUID(uuidString: pointDirectory.lastPathComponent) ?? UUID()
            return RecoveryPointMetadata(
                id: id,
                createdAt: directoryCreatedAt(pointDirectory) ?? .distantPast,
                reason: .restoreSafety,
                status: .invalid,
                schemaVersion: 0,
                appVersion: "",
                sourceLibraryID: nil,
                counts: RecoveryPointCounts(recordCount: 0, tagCount: 0, assetCount: 0),
                payloadSizeBytes: 0,
                files: []
            )
        }
    }

    func directoryCreatedAt(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    func writeMetadata(_ metadata: RecoveryPointMetadata, to pointDirectory: URL) throws {
        let metadataURL = pointDirectory.appendingPathComponent(Self.metadataFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: [.atomic])
    }
}
