import CryptoKit
import Foundation

struct BackupPackageArchive: Sendable {
    private static let magic = Data("HeatMomentBackup\n".utf8)
    private static let maxManifestByteCount: UInt64 = 10 * 1024 * 1024
    private static let chunkSize = 1024 * 1024

    static func write(
        manifest: BackupPackageManifest,
        payloadRootDirectory: URL,
        to destinationURL: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifestData = try encoder.encode(manifest)
        guard UInt64(manifestData.count) <= maxManifestByteCount else {
            throw BackupPackageError.invalidManifestLength(UInt64(manifestData.count))
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent("\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        try Data().write(to: temporaryURL, options: [.atomic])
        do {
            let output = try FileHandle(forWritingTo: temporaryURL)
            defer { try? output.close() }
            try output.write(contentsOf: magic)
            try output.write(contentsOf: UInt64(manifestData.count).backupPackageBytes)
            try output.write(contentsOf: manifestData)
            for payload in manifest.payloads {
                try validateRelativePath(payload.relativePath)
                let sourceURL = try absoluteURL(
                    forRelativePath: payload.relativePath,
                    rootDirectory: payloadRootDirectory
                )
                try copyFile(
                    from: sourceURL,
                    to: output,
                    expectedByteCount: payload.byteCount,
                    expectedSHA256: payload.sha256,
                    payloadPath: payload.relativePath
                )
            }
            try output.close()
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        } catch {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
            throw error
        }
    }

    static func extract(from archiveURL: URL, to destinationRootDirectory: URL) throws
        -> BackupPackageManifest {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationRootDirectory,
            withIntermediateDirectories: true
        )
        let input = try FileHandle(forReadingFrom: archiveURL)
        defer { try? input.close() }

        let actualMagic = try readExactData(from: input, byteCount: magic.count)
        guard actualMagic == magic else {
            throw BackupPackageError.invalidMagic
        }
        let manifestLengthData = try readExactData(from: input, byteCount: 8)
        let manifestLength = UInt64(backupPackageBytes: manifestLengthData)
        guard manifestLength <= maxManifestByteCount else {
            throw BackupPackageError.invalidManifestLength(manifestLength)
        }
        let manifestData = try readExactData(from: input, byteCount: Int(manifestLength))
        let manifest = try JSONDecoder().decode(BackupPackageManifest.self, from: manifestData)

        for payload in manifest.payloads {
            try validateRelativePath(payload.relativePath)
            let destinationURL = try absoluteURL(
                forRelativePath: payload.relativePath,
                rootDirectory: destinationRootDirectory
            )
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try copyFile(
                from: input,
                to: destinationURL,
                expectedByteCount: payload.byteCount,
                expectedSHA256: payload.sha256,
                payloadPath: payload.relativePath
            )
        }

        let trailingData = try input.read(upToCount: 1) ?? Data()
        guard trailingData.isEmpty else {
            throw BackupPackageError.unexpectedTrailingData
        }
        return manifest
    }

    static func absoluteURL(forRelativePath path: String, rootDirectory: URL) throws -> URL {
        try validateRelativePath(path)
        let url = rootDirectory.appendingPathComponent(path)
        let rootPath = rootDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            throw BackupPackageError.fileOutsideRoot(path)
        }
        return url
    }

    static func validatePayloads(in rootDirectory: URL, manifest: BackupPackageManifest) throws {
        for payload in manifest.payloads {
            let url = try absoluteURL(
                forRelativePath: payload.relativePath,
                rootDirectory: rootDirectory
            )
            let data = try Data(contentsOf: url)
            guard Int64(data.count) == payload.byteCount else {
                throw BackupPackageError.payloadByteCountMismatch(
                    path: payload.relativePath,
                    expected: payload.byteCount,
                    actual: Int64(data.count)
                )
            }
            let actualHash = FileAssetStore.sha256Hex(data)
            guard actualHash == payload.sha256 else {
                throw BackupPackageError.payloadHashMismatch(
                    path: payload.relativePath,
                    expected: payload.sha256,
                    actual: actualHash
                )
            }
        }
    }
}

private extension BackupPackageArchive {
    static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            throw BackupPackageError.invalidRelativePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw BackupPackageError.invalidRelativePath(path)
        }
    }

    static func copyFile(
        from sourceURL: URL,
        to output: FileHandle,
        expectedByteCount: Int64,
        expectedSHA256: String,
        payloadPath: String
    ) throws {
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }
        var hasher = SHA256()
        var actualByteCount: Int64 = 0
        while true {
            try Task.checkCancellation()
            let data = try input.read(upToCount: chunkSize) ?? Data()
            guard !data.isEmpty else { break }
            actualByteCount += Int64(data.count)
            hasher.update(data: data)
            try output.write(contentsOf: data)
        }
        try validateCopiedPayload(
            payloadPath: payloadPath,
            actualByteCount: actualByteCount,
            actualDigest: hasher.finalize(),
            expectedByteCount: expectedByteCount,
            expectedSHA256: expectedSHA256
        )
    }

    static func copyFile(
        from input: FileHandle,
        to destinationURL: URL,
        expectedByteCount: Int64,
        expectedSHA256: String,
        payloadPath: String
    ) throws {
        try Data().write(to: destinationURL, options: [.atomic])
        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }
        var hasher = SHA256()
        var remainingByteCount = expectedByteCount
        var actualByteCount: Int64 = 0
        while remainingByteCount > 0 {
            try Task.checkCancellation()
            let nextCount = min(Int64(chunkSize), remainingByteCount)
            let data = try input.read(upToCount: Int(nextCount)) ?? Data()
            guard !data.isEmpty else { break }
            remainingByteCount -= Int64(data.count)
            actualByteCount += Int64(data.count)
            hasher.update(data: data)
            try output.write(contentsOf: data)
        }
        try output.close()
        try validateCopiedPayload(
            payloadPath: payloadPath,
            actualByteCount: actualByteCount,
            actualDigest: hasher.finalize(),
            expectedByteCount: expectedByteCount,
            expectedSHA256: expectedSHA256
        )
    }

    static func validateCopiedPayload(
        payloadPath: String,
        actualByteCount: Int64,
        actualDigest: SHA256.Digest,
        expectedByteCount: Int64,
        expectedSHA256: String
    ) throws {
        guard actualByteCount == expectedByteCount else {
            throw BackupPackageError.payloadByteCountMismatch(
                path: payloadPath,
                expected: expectedByteCount,
                actual: actualByteCount
            )
        }
        let actualSHA256 = actualDigest.map { String(format: "%02x", $0) }.joined()
        guard actualSHA256 == expectedSHA256 else {
            throw BackupPackageError.payloadHashMismatch(
                path: payloadPath,
                expected: expectedSHA256,
                actual: actualSHA256
            )
        }
    }

    static func readExactData(from input: FileHandle, byteCount: Int) throws -> Data {
        var data = Data()
        var remainingByteCount = byteCount
        while remainingByteCount > 0 {
            let chunk = try input.read(upToCount: remainingByteCount) ?? Data()
            guard !chunk.isEmpty else {
                throw BackupPackageError.payloadByteCountMismatch(
                    path: "archive-header",
                    expected: Int64(byteCount),
                    actual: Int64(data.count)
                )
            }
            data.append(chunk)
            remainingByteCount -= chunk.count
        }
        return data
    }
}

private extension UInt64 {
    var backupPackageBytes: Data {
        Data((0..<8).map { shift in
            UInt8((self >> UInt64((7 - shift) * 8)) & 0xff)
        })
    }

    init(backupPackageBytes data: Data) {
        self = data.reduce(UInt64(0)) { partial, byte in
            (partial << 8) | UInt64(byte)
        }
    }
}
