import Foundation

struct BackupPackageExportHistoryStore: Sendable {
    static let defaultKey = "HeatMoment.BackupPackage.LastExportSnapshot"
    private static let legacyExportedAtKey = "HeatMoment.BackupPackage.LastExportedAt"

    private let key: String

    init(key: String = Self.defaultKey) {
        self.key = key
    }

    func lastExportSnapshot() throws -> BackupPackageExportSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        return try JSONDecoder().decode(BackupPackageExportSnapshot.self, from: data)
    }

    func recordExportSnapshot(_ snapshot: BackupPackageExportSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.removeObject(forKey: Self.legacyExportedAtKey)
    }

    func removeExportSnapshot() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: Self.legacyExportedAtKey)
    }
}
