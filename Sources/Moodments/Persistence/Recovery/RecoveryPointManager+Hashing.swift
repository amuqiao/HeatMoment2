import CryptoKit
import Foundation

extension RecoveryPointManager {
    func fileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024)
            guard let data, !data.isEmpty else { break }
            data.withUnsafeBytes { buffer in
                hasher.update(bufferPointer: buffer)
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension URL {
    func relativePath(from root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let path = standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else {
            throw RecoveryPointError.sourceFileOutsideRoot(file: self, root: root)
        }
        return String(path.dropFirst(rootPath.count + 1))
    }
}
