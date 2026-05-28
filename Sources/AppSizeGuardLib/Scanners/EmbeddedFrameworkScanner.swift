import Foundation

/// Reports embedded `.framework` sizes from the built app bundle (`App.app/Frameworks`).
public struct EmbeddedFrameworkScanner {
    public let context: BuildContext
    public let config: AppSizeGuardConfig

    public func scan() -> [Diagnostic] {
        guard let appPath = context.appBundlePath else { return [] }
        let frameworksDir = (appPath as NSString).appendingPathComponent("Frameworks")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: frameworksDir, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let warnBytes = Int64(config.dependencyWarnSizeMB) * 1024 * 1024
        var diagnostics: [Diagnostic] = []
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: frameworksDir) else { return [] }

        for item in items where item.hasSuffix(".framework") {
            let path = (frameworksDir as NSString).appendingPathComponent(item)
            let name = (item as NSString).deletingPathExtension
            let size = DirectoryWalker.directorySize(at: path)
            guard size >= warnBytes else { continue }
            let formatted = formatBytes(size)
            diagnostics.append(Diagnostic(
                severity: .warning,
                category: .dependencies,
                path: path,
                message: "Embedded framework '\(name)' — \(formatted) (exceeds \(config.dependencyWarnSizeMB)MB threshold)"
            ))
        }
        return diagnostics
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1024.0
        return String(format: "%.0f KB", kb)
    }
}
