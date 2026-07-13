import XCTest
@testable import HeatMoment

final class FileAssetStoreTests: XCTestCase {
    func testStoreWritesContentAddressedAssetAndReadsItBack() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAssetStore(rootDirectory: directory)
        let data = Data([0x01, 0x02, 0x03])

        let stored = try store.store(data: data)

        XCTAssertEqual(stored.contentHash, FileAssetStore.sha256Hex(data))
        XCTAssertEqual(stored.byteCount, data.count)
        XCTAssertTrue(stored.didCreateFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.fileURL.path))
        XCTAssertEqual(try store.data(forContentHash: stored.contentHash), data)
    }

    func testStoreDeduplicatesByContentHash() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAssetStore(rootDirectory: directory)
        let data = Data([0x04, 0x05, 0x06])

        let first = try store.store(data: data)
        let second = try store.store(data: data)

        XCTAssertTrue(first.didCreateFile)
        XCTAssertFalse(second.didCreateFile)
        XCTAssertEqual(first.fileURL, second.fileURL)
        XCTAssertEqual(try storedBlobCount(in: directory), 1)
    }

    func testExpectedHashMismatchFailsWithoutWritingBlob() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAssetStore(rootDirectory: directory)

        do {
            _ = try store.store(
                data: Data([0x07]), expectedContentHash: String(repeating: "0", count: 64))
            XCTFail("期望 content hash 不一致时写入失败")
        } catch FileAssetStoreError.contentHashMismatch(let expected, let actual) {
            XCTAssertEqual(expected, String(repeating: "0", count: 64))
            XCTAssertNotEqual(actual, expected)
        } catch {
            XCTFail("期望 FileAssetStoreError.contentHashMismatch，实际抛出 \(error)")
        }

        XCTAssertEqual(try storedBlobCount(in: directory), 0)
    }

    func testExistingBlobContentMismatchFails() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAssetStore(rootDirectory: directory)
        let data = Data([0x08, 0x09])
        let stored = try store.store(data: data)
        try Data([0x10]).write(to: stored.fileURL, options: [.atomic])

        do {
            _ = try store.store(data: data)
            XCTFail("期望已存在 blob 内容损坏时复用失败")
        } catch FileAssetStoreError.contentHashMismatch(let expected, let actual) {
            XCTAssertEqual(expected, stored.contentHash)
            XCTAssertNotEqual(actual, expected)
        } catch {
            XCTFail("期望 FileAssetStoreError.contentHashMismatch，实际抛出 \(error)")
        }
    }

    func testListValidateAndRemoveBlob() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAssetStore(rootDirectory: directory)
        let data = Data([0x11, 0x12])
        let stored = try store.store(data: data)

        let listing = try store.listStoredAssets()
        let validated = try store.validateStoredAsset(forContentHash: stored.contentHash)

        XCTAssertEqual(listing.contentHashes, [stored.contentHash])
        XCTAssertTrue(listing.invalidRelativePaths.isEmpty)
        XCTAssertEqual(validated.contentHash, stored.contentHash)

        try store.removeBlob(forContentHash: stored.contentHash)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.fileURL.path))
        XCTAssertThrowsError(try store.validateStoredAsset(forContentHash: stored.contentHash)) {
            // swiftlint:disable:next closure_parameter_position
            error in
            XCTAssertEqual(error as? FileAssetStoreError, .missingAsset(stored.contentHash))
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FileAssetStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func storedBlobCount(in directory: URL) throws -> Int {
        let blobsDirectory = directory.appendingPathComponent("blobs", isDirectory: true)
        guard
            let enumerator = FileManager.default.enumerator(
                at: blobsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                count += 1
            }
        }
        return count
    }
}
