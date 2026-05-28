import Foundation
import Yams

public struct AppSizeGuardConfig: Equatable {
    public var isProduction: Bool
    public var thresholds: [String: FileThreshold]
    public var growthWarnPercent: Double
    public var growthErrorPercent: Double
    public var dependencyWarnSizeMB: Int
    public var spmDependencyWarnSizeMB: Int
    public var stagingZipPatterns: [String]

    public struct FileThreshold: Equatable {
        public var warnKB: Int
        public var errorKB: Int
    }

    public static let defaultThresholdKB = (warn: 500, error: 1024)

    public static func load(from url: URL) throws -> AppSizeGuardConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .defaults
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let yaml = try Yams.load(yaml: text) as? [String: Any] else {
            return .defaults
        }
        return parse(yaml)
    }

    public static var defaults: AppSizeGuardConfig {
        AppSizeGuardConfig(
            isProduction: true,
            thresholds: defaultThresholds(),
            growthWarnPercent: 5,
            growthErrorPercent: 15,
            dependencyWarnSizeMB: 10,
            spmDependencyWarnSizeMB: 3,
            stagingZipPatterns: ["*staging*", "appinit_staging.zip"]
        )
    }

    static func defaultThresholds() -> [String: FileThreshold] {
        let types = ["png", "jpg", "jpeg", "gif", "json", "mp4", "mov", "m4a", "wav", "mp3", "ttf", "otf", "pdf"]
        return Dictionary(uniqueKeysWithValues: types.map { ext in
            (ext, FileThreshold(warnKB: defaultThresholdKB.warn, errorKB: defaultThresholdKB.error))
        })
    }

    private static func parse(_ yaml: [String: Any]) -> AppSizeGuardConfig {
        var config = defaults
        if let prod = yaml["is_production"] as? Bool {
            config.isProduction = prod
        }
        if let growth = yaml["growth"] as? [String: Any] {
            if let w = growth["warn_percent"] as? Double { config.growthWarnPercent = w }
            if let w = growth["warn_percent"] as? Int { config.growthWarnPercent = Double(w) }
            if let e = growth["error_percent"] as? Double { config.growthErrorPercent = e }
            if let e = growth["error_percent"] as? Int { config.growthErrorPercent = Double(e) }
        }
        if let deps = yaml["dependencies"] as? [String: Any] {
            if let mb = deps["warn_size_mb"] as? Int { config.dependencyWarnSizeMB = mb }
            if let spm = deps["spm_warn_size_mb"] as? Int { config.spmDependencyWarnSizeMB = spm }
        }
        if let patterns = yaml["staging_zip_patterns"] as? [String] {
            config.stagingZipPatterns = patterns
        }
        if let thresholds = yaml["thresholds"] as? [String: Any] {
            for (ext, value) in thresholds {
                guard let dict = value as? [String: Any] else { continue }
                let warn = (dict["warn_kb"] as? Int) ?? defaultThresholdKB.warn
                let error = (dict["error_kb"] as? Int) ?? defaultThresholdKB.error
                config.thresholds[ext.lowercased()] = FileThreshold(warnKB: warn, errorKB: error)
            }
        }
        return config
    }

    public func threshold(forExtension ext: String) -> FileThreshold {
        let key = ext.lowercased()
        if let t = thresholds[key] { return t }
        if key == "jpeg", let t = thresholds["jpg"] { return t }
        return FileThreshold(warnKB: Self.defaultThresholdKB.warn, errorKB: Self.defaultThresholdKB.error)
    }
}
