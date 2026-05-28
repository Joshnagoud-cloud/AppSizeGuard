import Foundation

public struct DuplicateAssetsScanner {
    public let resourcePaths: [String]
    public let reporter: XcodeDiagnosticReporter

    public func scan() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let hashableExts = Set(["png", "jpg", "jpeg", "gif", "pdf", "json"])
        var groups: [String: [String]] = [:]

        for path in resourcePaths {
            let ext = (path as NSString).pathExtension.lowercased()
            guard hashableExts.contains(ext) else { continue }
            if path.contains(".xcassets/") { continue }

            guard let hash = ContentHasher.sha256(of: path) else {
                if let size = DirectoryWalker.fileSize(at: path), size > ContentHasher.maxHashFileBytes {
                    reporter.emit(Diagnostic(
                        severity: .note,
                        category: .duplicates,
                        path: path,
                        message: "Skipped duplicate check: file exceeds hash size cap"
                    ))
                }
                continue
            }
            groups[hash, default: []].append(path)
        }

        for (_, paths) in groups where paths.count > 1 {
            let sorted = paths.sorted()
            let names = sorted.map { ($0 as NSString).lastPathComponent }.joined(separator: "', '")
            diagnostics.append(Diagnostic(
                severity: .warning,
                category: .duplicates,
                path: sorted[0],
                message: "Duplicate assets (identical SHA256): '\(names)'"
            ))
        }
        return diagnostics
    }
}
