import Foundation
import GRDB

enum CanonicalMomentLifecycleState: String, Sendable, Equatable {
    case active
    case softDeleted
    case purgePending
    case purged
}

struct CanonicalMomentRecord: Sendable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let bodyText: String
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date
    let mood: Mood
    let tagIDs: [UUID]
    let lifecycleState: CanonicalMomentLifecycleState
    let deletedAt: Date?
    let purgedAt: Date?
    let revision: Int

    var isDeleted: Bool { lifecycleState == .softDeleted }

    var isTerminalDeletion: Bool {
        lifecycleState == .purgePending || lifecycleState == .purged
    }
}

struct CanonicalTagRecord: Sendable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date
    let revision: Int
}

struct CanonicalMutationRecord: Sendable, Identifiable, Equatable {
    let id: UUID
    let entityType: String
    let entityID: UUID
    let operation: String
    let occurredAt: Date
    let deviceID: UUID
    let recordRevision: Int
}

struct CanonicalLibraryMetadata: Sendable, Equatable {
    let libraryID: UUID
    let schemaVersion: Int
    let deviceID: UUID
    let syncEpoch: UUID
    let createdAt: Date
    let updatedAt: Date
    let swiftDataImportedAt: Date?
    let swiftDataImportSourceFingerprint: String?
}

extension Date {
    fileprivate init(canonicalTimestamp: Double) {
        self.init(timeIntervalSince1970: canonicalTimestamp)
    }

    fileprivate var canonicalTimestamp: Double {
        timeIntervalSince1970
    }
}

extension UUID {
    init(canonicalString: String) throws {
        guard let uuid = UUID(uuidString: canonicalString) else {
            throw DatabaseError(message: "Invalid UUID: \(canonicalString)")
        }
        self = uuid
    }
}

extension Row {
    func canonicalUUID(_ column: String) throws -> UUID {
        try UUID(canonicalString: self[column])
    }

    func canonicalDate(_ column: String) -> Date {
        Date(canonicalTimestamp: self[column])
    }

    func canonicalOptionalDate(_ column: String) -> Date? {
        let value: Double? = self[column]
        return value.map(Date.init(canonicalTimestamp:))
    }
}
