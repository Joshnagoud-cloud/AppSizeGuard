import Foundation

public struct OversizedAssetsScanner {
    public let config: AppSizeGuardConfig
    public let resourcePaths: [String]

    public func scan() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let assetExts = Set(["png", "jpg", "jpeg", "gif", "pdf", "json", "mp4", "mov", "m4a", "wav", "mp3", "aac", "ttf", "otf"])

        for path in resourcePaths {
            guard SourceAssetFilter.isScannableSourceAsset(path) else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            guard assetExts.contains(ext) else { continue }
            // Skip catalog metadata only; PDF/PNG inside .imageset are valid source assets.
            if path.hasSuffix("Contents.json") && path.contains(".xcassets/") { continue }
            guard let bytes = DirectoryWalker.fileSize(at: path) else { continue }

            let threshold = config.threshold(forExtension: ext)
            let warnBytes = Int64(threshold.warnKB) * 1024
            let errorBytes = Int64(threshold.errorKB) * 1024
            let displayName = displayName(for: path)
            let sizeLabel = formatSize(bytes)

            // Per spec: by default show warnings only (never use Xcode error severity for assets).
            if bytes >= errorBytes {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    category: .assets,
                    path: path,
                    message: "Oversized \(ext.uppercased()): '\(displayName)' — \(sizeLabel) (exceeds \(threshold.errorKB) KB limit)"
                ))
            } else if bytes >= warnBytes {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    category: .assets,
                    path: path,
                    message: "Oversized \(ext.uppercased()): '\(displayName)' — \(sizeLabel) (exceeds \(threshold.warnKB) KB limit)"
                ))
            }
        }
        return diagnostics
    }

    /// Uses imageset name for PDF/PNG inside `.xcassets` (matches `UIImage(named:)`); otherwise the file name.
    private func displayName(for path: String) -> String {
        if path.contains(".xcassets/"),
           let setName = ResourceReferenceExtractor().imagesetName(from: path) {
            return setName
        }
        return (path as NSString).lastPathComponent
    }

    private func formatSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        if kb >= 1024 { return String(format: "%.1f MB", kb / 1024.0) }
        return String(format: "%.0f KB", kb)
    }
}
