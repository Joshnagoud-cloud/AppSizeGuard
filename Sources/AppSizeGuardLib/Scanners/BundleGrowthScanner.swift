import Foundation

public struct BundleGrowthScanner {
    public let context: BuildContext
    public let config: AppSizeGuardConfig

    public struct Breakdown: Codable, Equatable {
        public var resources: Int64
        public var frameworks: Int64
        public var executable: Int64
        public var other: Int64
    }

    public struct BaselineEntry: Codable, Equatable {
        public var buildDate: String
        public var appVersion: String
        public var totalBytes: Int64
        public var breakdown: Breakdown
    }

    public func scan() -> [Diagnostic] {
        guard context.isDebug else { return [] }
        guard let appPath = context.appBundlePath else {
            var diagnostics: [Diagnostic] = [
                Diagnostic(
                    severity: .note,
                    category: .growth,
                    path: context.srcroot,
                    message: "Growth skipped — .app not found under BUILT_PRODUCTS_DIR (place Run Script after Copy Bundle Resources)"
                ),
            ]
            if context.shouldUpdateBaseline {
                diagnostics.append(Diagnostic(
                    severity: .note,
                    category: .growth,
                    path: context.baselineURL.path,
                    message: "Baseline not updated — .app bundle missing; cannot measure size"
                ))
            }
            return diagnostics
        }

        var diagnostics: [Diagnostic] = []
        let currentTotal = DirectoryWalker.directorySize(at: appPath)
        let breakdown = measureBreakdown(appPath: appPath)
        let version = readAppVersion(appPath: appPath)

        switch loadBaseline(configuration: context.configuration) {
        case .missing:
            diagnostics.append(Diagnostic(
                severity: .note,
                category: .growth,
                path: context.baselineURL.path,
                message: "Growth skipped — add '.appsizeguard-baseline.json' at SRCROOT with a '\(context.configuration)' entry, or set APPSIZEGUARD_UPDATE_BASELINE=1 in CI to seed after a Debug build"
            ))
        case .unseeded:
            diagnostics.append(Diagnostic(
                severity: .note,
                category: .growth,
                path: context.baselineURL.path,
                message: "Growth skipped — baseline '\(context.configuration).total_mb' is 0; seed via CI (APPSIZEGUARD_UPDATE_BASELINE=1) after a successful Debug build"
            ))
        case .loaded(let baseline):
            let previous = baseline.totalBytes
            let growth = (Double(currentTotal - previous) / Double(previous)) * 100.0
            if growth >= config.growthErrorPercent {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    category: .growth,
                    path: appPath,
                    message: String(
                        format: "App bundle grew %.1f%% (%@ → %@) since baseline (error threshold %.0f%%)",
                        growth, formatBytes(previous), formatBytes(currentTotal), config.growthErrorPercent
                    )
                ))
            } else if growth >= config.growthWarnPercent {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    category: .growth,
                    path: appPath,
                    message: String(
                        format: "App bundle grew %.1f%% (%@ → %@) since baseline (warn threshold %.0f%%)",
                        growth, formatBytes(previous), formatBytes(currentTotal), config.growthWarnPercent
                    )
                ))
            }
        }

        if context.shouldUpdateBaseline {
            let entry = BaselineEntry(
                buildDate: ISO8601DateFormatter().string(from: Date()),
                appVersion: version,
                totalBytes: currentTotal,
                breakdown: breakdown
            )
            if writeBaseline(configuration: context.configuration, entry: entry) {
                diagnostics.append(Diagnostic(
                    severity: .note,
                    category: .growth,
                    path: context.baselineURL.path,
                    message: "Baseline updated for '\(context.configuration)' — \(formatBytes(currentTotal)) (app version \(version))"
                ))
            } else {
                diagnostics.append(Diagnostic(
                    severity: .note,
                    category: .growth,
                    path: context.baselineURL.path,
                    message: "Baseline update failed — could not write '\(context.baselineURL.lastPathComponent)' at SRCROOT"
                ))
            }
        }

        return diagnostics
    }

    private enum BaselineLoadResult {
        case missing
        case unseeded
        case loaded(BaselineEntry)
    }

    private func loadBaseline(configuration: String) -> BaselineLoadResult {
        guard FileManager.default.fileExists(atPath: context.baselineURL.path),
              let data = try? Data(contentsOf: context.baselineURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .missing
        }

        let key = json.keys.first { $0.caseInsensitiveCompare(configuration) == .orderedSame } ?? configuration
        guard let entryDict = json[key] as? [String: Any],
              let entry = decodeEntry(entryDict) else {
            return .missing
        }
        if entry.totalBytes <= 0 {
            return .unseeded
        }
        return .loaded(entry)
    }

    private func measureBreakdown(appPath: String) -> Breakdown {
        var breakdown = Breakdown(resources: 0, frameworks: 0, executable: 0, other: 0)
        let fm = FileManager.default
        guard let top = try? fm.contentsOfDirectory(atPath: appPath) else { return breakdown }

        if let execName = mainExecutableName(appPath: appPath) {
            let execPath = (appPath as NSString).appendingPathComponent(execName)
            breakdown.executable = DirectoryWalker.fileSize(at: execPath) ?? 0
        }

        for item in top {
            let path = (appPath as NSString).appendingPathComponent(item)
            if item == (mainExecutableName(appPath: appPath) ?? "") { continue }
            let size = DirectoryWalker.fileSize(at: path) ?? DirectoryWalker.directorySize(at: path)
            switch item {
            case "Frameworks":
                breakdown.frameworks += DirectoryWalker.directorySize(at: path)
            case "PlugIns":
                breakdown.other += DirectoryWalker.directorySize(at: path)
            case "Info.plist":
                breakdown.resources += size
            default:
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                    breakdown.resources += DirectoryWalker.directorySize(at: path)
                } else {
                    breakdown.resources += size
                }
            }
        }
        return breakdown
    }

    private func mainExecutableName(appPath: String) -> String? {
        let plistPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let plist = NSDictionary(contentsOfFile: plistPath),
              let name = plist["CFBundleExecutable"] as? String else { return nil }
        return name
    }

    private func readAppVersion(appPath: String) -> String {
        let plistPath = (appPath as NSString).appendingPathComponent("Info.plist")
        guard let plist = NSDictionary(contentsOfFile: plistPath) else { return "unknown" }
        return (plist["CFBundleShortVersionString"] as? String) ?? "unknown"
    }

    @discardableResult
    private func writeBaseline(configuration: String, entry: BaselineEntry) -> Bool {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: context.baselineURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }
        root[configuration] = encodeEntry(entry)
        guard JSONSerialization.isValidJSONObject(root),
              let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        do {
            try out.write(to: context.baselineURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func decodeEntry(_ dict: [String: Any]) -> BaselineEntry? {
        guard let buildDate = dict["build_date"] as? String,
              let appVersion = dict["app_version"] as? String else { return nil }
        guard let totalBytes = decodeTotalBytes(from: dict) else { return nil }
        let b = dict["breakdown"] as? [String: Any] ?? [:]
        let breakdown = Breakdown(
            resources: decodeBreakdownBytes(from: b, field: "resources"),
            frameworks: decodeBreakdownBytes(from: b, field: "frameworks"),
            executable: decodeBreakdownBytes(from: b, field: "executable"),
            other: decodeBreakdownBytes(from: b, field: "other")
        )
        return BaselineEntry(buildDate: buildDate, appVersion: appVersion, totalBytes: totalBytes, breakdown: breakdown)
    }

    private func decodeTotalBytes(from dict: [String: Any]) -> Int64? {
        if let mb = doubleValue(dict["total_mb"]) {
            return mbToBytes(mb)
        }
        if let bytes = int64Value(dict["total_bytes"]) {
            return bytes
        }
        return nil
    }

    private func decodeBreakdownBytes(from dict: [String: Any], field: String) -> Int64 {
        if let mb = doubleValue(dict["\(field)_mb"]) {
            return mbToBytes(mb)
        }
        return int64Value(dict[field]) ?? 0
    }

    private func encodeEntry(_ entry: BaselineEntry) -> [String: Any] {
        [
            "build_date": entry.buildDate,
            "app_version": entry.appVersion,
            "total_mb": bytesToMB(entry.totalBytes),
            "breakdown": [
                "resources_mb": bytesToMB(entry.breakdown.resources),
                "frameworks_mb": bytesToMB(entry.breakdown.frameworks),
                "executable_mb": bytesToMB(entry.breakdown.executable),
                "other_mb": bytesToMB(entry.breakdown.other),
            ],
        ]
    }

    private func bytesToMB(_ bytes: Int64) -> Double {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return (mb * 100).rounded() / 100
    }

    private func mbToBytes(_ mb: Double) -> Int64 {
        Int64((mb * 1024.0 * 1024.0).rounded())
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private func int64Value(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let i = value as? Int { return Int64(i) }
        if let i = value as? Int64 { return i }
        return nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1.0 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", Double(bytes) / 1024.0)
    }
}
