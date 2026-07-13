import Foundation

struct BackupPackageExportHistoryStore: Sendable {
    private let key: String

    init(key: String = "HeatMoment.BackupPackage.LastExportedAt") {
        self.key = key
    }

    func lastExportedAt() -> Date? {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return nil
        }
        return Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: key))
    }

    func recordExported(at date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
    }
}
