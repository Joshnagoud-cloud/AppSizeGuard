import Foundation
import CryptoKit

public enum ContentHasher {
    public static let maxHashFileBytes: Int64 = 50 * 1024 * 1024

    public static func sha256(of path: String) -> String? {
        guard let size = DirectoryWalker.fileSize(at: path), size <= maxHashFileBytes else { return nil }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 65536)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func normalizedBaseName(for path: String) -> String {
        var name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if let range = name.range(of: "@\\d+x$", options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }
}
