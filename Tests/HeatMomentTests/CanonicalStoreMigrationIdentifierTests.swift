import GRDB
import XCTest
@testable import HeatMoment

final class CanonicalStoreMigrationIdentifierTests: XCTestCase {
    func testMigrationKeepsExistingV2IdentifierStable() throws {
        let store = try CanonicalStore.makeInMemory()
        let appliedMigrations = try store.read { db in
            try Set(String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations"))
        }

        XCTAssertTrue(appliedMigrations.contains("v2_swift_data_import_marker"))
        XCTAssertFalse(appliedMigrations.contains("v2_canonical_metadata_version"))
    }
}
