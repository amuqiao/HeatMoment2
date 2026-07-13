import Foundation

enum CanonicalBootRestoreGate {
    static func performProductionPendingRestoreIfNeeded(
        now: Date = .now
    ) throws -> CanonicalBootRestoreResult {
        try performPendingRestoreIfNeeded(
            descriptor: CanonicalLibraryRuntime.productionDescriptor,
            now: now
        )
    }

    static func performPendingRestoreIfNeeded(
        descriptor: CanonicalStoreDescriptor,
        now: Date = .now
    ) throws -> CanonicalBootRestoreResult {
        try performPendingRestoreIfNeeded(
            descriptor: descriptor,
            now: now,
            replaceStorePayload: { payloadDirectory, descriptor in
                try CanonicalRestoreExecutor.replaceStorePayload(
                    from: payloadDirectory,
                    descriptor: descriptor
                )
            }
        )
    }

    static func performPendingRestoreIfNeeded(
        descriptor: CanonicalStoreDescriptor,
        now: Date = .now,
        replaceStorePayload: (URL, CanonicalStoreDescriptor) throws -> Void
    ) throws -> CanonicalBootRestoreResult {
        try CanonicalRestoreExecutor.performPendingRestoreIfNeeded(
            descriptor: descriptor,
            now: now,
            replaceStorePayload: replaceStorePayload
        )
    }
}
