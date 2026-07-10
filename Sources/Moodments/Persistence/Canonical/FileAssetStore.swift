import CryptoKit
import Foundation

enum FileAssetStoreError: Error, Equatable {
    case contentHashMismatch(expected: String, actual: String)
    case missingAsset(String)
    case invalidAssetHash(String)
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

    func removeStoredAsset(_ asset: StoredFileAsset) throws {
        guard asset.didCreateFile else { return }
        if FileManager.default.fileExists(atPath: asset.fileURL.path) {
            try FileManager.default.removeItem(at: asset.fileURL)
        }
    }

    func fileURL(forContentHash contentHash: String) throws -> URL {
        guard contentHash.count >= 2, contentHash.allSatisfy(\.isHexDigit) else {
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
}
