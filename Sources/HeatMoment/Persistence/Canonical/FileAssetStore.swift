import CryptoKit
import Foundation

enum FileAssetStoreError: Error, Equatable {
    case contentHashMismatch(expected: String, actual: String)
    case missingAsset(String)
    case invalidAssetHash(String)
    case assetEnumerationUnavailable(String)
}

struct FileAssetStoreListing: Sendable, Equatable {
    let contentHashes: [String]
    let invalidRelativePaths: [String]
}

struct StoredFileAsset: Sendable, Equatable {
    let contentHash: String
    let byteCount: Int
    let fileURL: URL
    let didCreateFile: Bool
}

struct FileAssetStore: Sendable {
    let rootDirectory: URL

    func store(data: Data, expectedContentHash: String? = nil) throws -> StoredFileAsset {
        let contentHash = Self.sha256Hex(data)
        if let expectedContentHash, expectedContentHash != contentHash {
            throw FileAssetStoreError.contentHashMismatch(
                expected: expectedContentHash,
                actual: contentHash
            )
        }

        let fileURL = try fileURL(forContentHash: contentHash)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try existingStoredAsset(fileURL: fileURL, expectedContentHash: contentHash)
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let stagingDirectory = rootDirectory.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        let temporaryURL = stagingDirectory.appendingPathComponent("\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: [.atomic])
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: fileURL)
        } catch {
            if FileManager.default.fileExists(atPath: temporaryURL.path) {
                try FileManager.default.removeItem(at: temporaryURL)
            }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return try existingStoredAsset(fileURL: fileURL, expectedContentHash: contentHash)
            }
            throw error
        }
        return StoredFileAsset(
            contentHash: contentHash,
            byteCount: data.count,
            fileURL: fileURL,
            didCreateFile: true
        )
    }

    func data(forContentHash contentHash: String) throws -> Data {
        let url = try fileURL(forContentHash: contentHash)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAssetStoreError.missingAsset(contentHash)
        }
        return try Data(contentsOf: url)
    }

    func validateStoredAsset(forContentHash contentHash: String) throws -> StoredFileAsset {
        let url = try fileURL(forContentHash: contentHash)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAssetStoreError.missingAsset(contentHash)
        }
        return try existingStoredAsset(fileURL: url, expectedContentHash: contentHash)
    }

    func removeStoredAsset(_ asset: StoredFileAsset) throws {
        guard asset.didCreateFile else { return }
        if FileManager.default.fileExists(atPath: asset.fileURL.path) {
            try FileManager.default.removeItem(at: asset.fileURL)
        }
    }

    func removeBlob(forContentHash contentHash: String) throws {
        let url = try fileURL(forContentHash: contentHash)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileAssetStoreError.missingAsset(contentHash)
        }
        try FileManager.default.removeItem(at: url)
    }

    func listStoredAssets() throws -> FileAssetStoreListing {
        let blobsDirectory = rootDirectory.appendingPathComponent("blobs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: blobsDirectory.path) else {
            return FileAssetStoreListing(contentHashes: [], invalidRelativePaths: [])
        }
        guard
            let enumerator = FileManager.default.enumerator(
                at: blobsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else {
            throw FileAssetStoreError.assetEnumerationUnavailable(blobsDirectory.path)
        }

        var contentHashes: Set<String> = []
        var invalidRelativePaths: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let contentHash = url.lastPathComponent
            let prefix = url.deletingLastPathComponent().lastPathComponent
            if Self.isValidContentHash(contentHash) && prefix == String(contentHash.prefix(2)) {
                contentHashes.insert(contentHash)
            } else {
                invalidRelativePaths.append(relativePath(for: url))
            }
        }

        return FileAssetStoreListing(
            contentHashes: contentHashes.sorted(),
            invalidRelativePaths: invalidRelativePaths.sorted()
        )
    }

    func fileURL(forContentHash contentHash: String) throws -> URL {
        guard Self.isValidContentHash(contentHash) else {
            throw FileAssetStoreError.invalidAssetHash(contentHash)
        }
        let prefix = String(contentHash.prefix(2))
        return
            rootDirectory
            .appendingPathComponent("blobs", isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(contentHash)
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func isValidContentHash(_ contentHash: String) -> Bool {
        contentHash.count == 64 && contentHash.allSatisfy(\.isHexDigit)
    }

    private func existingStoredAsset(
        fileURL: URL,
        expectedContentHash: String
    ) throws -> StoredFileAsset {
        let existingData = try Data(contentsOf: fileURL)
        let actualContentHash = Self.sha256Hex(existingData)
        guard actualContentHash == expectedContentHash else {
            throw FileAssetStoreError.contentHashMismatch(
                expected: expectedContentHash,
                actual: actualContentHash
            )
        }
        return StoredFileAsset(
            contentHash: expectedContentHash,
            byteCount: existingData.count,
            fileURL: fileURL,
            didCreateFile: false
        )
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = rootDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return path
        }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
