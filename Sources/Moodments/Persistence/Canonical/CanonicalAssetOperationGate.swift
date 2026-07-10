import Foundation

final class CanonicalAssetOperationGate: @unchecked Sendable {
    private static let registryLock = NSLock()
    // Protected by registryLock.
    nonisolated(unsafe) private static var gatesByAssetRootPath:
        [String: CanonicalAssetOperationGate] = [:]

    private let lock = NSRecursiveLock()

    static func shared(
        forAssetRootDirectory assetRootDirectory: URL
    ) -> CanonicalAssetOperationGate {
        let path = assetRootDirectory.standardizedFileURL.path
        registryLock.lock()
        defer { registryLock.unlock() }

        if let gate = gatesByAssetRootPath[path] {
            return gate
        }
        let gate = CanonicalAssetOperationGate()
        gatesByAssetRootPath[path] = gate
        return gate
    }

    func performSync<Value>(
        _ operation: () throws -> Value
    ) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
