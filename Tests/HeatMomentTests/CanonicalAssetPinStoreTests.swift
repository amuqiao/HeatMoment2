import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalAssetPinStoreTests: XCTestCase {
    func testPinContentHashUpsertsByOwnerAndRelease() throws {
        let store = try CanonicalStore.makeInMemory()
        let pinStore = CanonicalAssetPinStore(store: store)
        let contentHash = FileAssetStore.sha256Hex(Data([0x01, 0x02]))
        let ownerID = UUID().uuidString

        let first = try pinStore.pinContentHash(
            contentHash,
            ownerKind: .exportJob,
            ownerID: ownerID,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        let second = try pinStore.pinContentHash(
            contentHash,
            ownerKind: .exportJob,
            ownerID: ownerID,
            createdAt: Date(timeIntervalSince1970: 120),
            expiresAt: Date(timeIntervalSince1970: 240)
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.expiresAt, Date(timeIntervalSince1970: 240))
        XCTAssertEqual(try pinCount(in: store), 1)
        XCTAssertTrue(
            try pinStore.releaseContentHashPin(
                contentHash: contentHash,
                ownerKind: .exportJob,
                ownerID: ownerID
            )
        )
        XCTAssertFalse(
            try pinStore.releaseContentHashPin(
                contentHash: contentHash,
                ownerKind: .exportJob,
                ownerID: ownerID
            )
        )
        XCTAssertEqual(try pinCount(in: store), 0)
    }

    func testPinValidationRejectsInvalidHashOwnerAndExpiration() throws {
        let store = try CanonicalStore.makeInMemory()
        let pinStore = CanonicalAssetPinStore(store: store)
        let contentHash = FileAssetStore.sha256Hex(Data([0x03, 0x04]))

        XCTAssertThrowsError(
            try pinStore.pinContentHash(
                "sha256-invalid",
                ownerKind: .recoveryPoint,
                ownerID: "recovery-1"
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalAssetPinStoreError,
                .invalidContentHash("sha256-invalid")
            )
        }
        XCTAssertThrowsError(
            try pinStore.pinContentHash(
                contentHash,
                ownerKind: .recoveryPoint,
                ownerID: ""
            )
        ) { error in
            XCTAssertEqual(error as? CanonicalAssetPinStoreError, .invalidOwnerID)
        }
        XCTAssertThrowsError(
            try pinStore.pinContentHash(
                contentHash,
                ownerKind: .restoreStaging,
                ownerID: "restore-1",
                createdAt: Date(timeIntervalSince1970: 200),
                expiresAt: Date(timeIntervalSince1970: 100)
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalAssetPinStoreError,
                .invalidExpiration(
                    createdAt: Date(timeIntervalSince1970: 200),
                    expiresAt: Date(timeIntervalSince1970: 100)
                )
            )
        }
        XCTAssertEqual(try pinCount(in: store), 0)
    }

    private func pinCount(in store: CanonicalStore) throws -> Int {
        try store.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset_pin_record") ?? 0
        }
    }
}
