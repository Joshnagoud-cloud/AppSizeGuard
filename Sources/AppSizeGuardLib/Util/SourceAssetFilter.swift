import Foundation

/// Filters paths to v1 in-scope **source** app resources (excludes embedded frameworks, Swift modules, Pods, etc.).
public enum SourceAssetFilter {
    private static let excludedPathFragments = [
        ".framework/",
        ".xcframework/",
        ".swiftmodule/",
        ".bundle/",
        "/Pods/",
        "/Carthage/",
        "/DerivedData/",
        "/SourcePackages/",
    ]

    private static let excludedFileSuffixes = [
        ".abi.json",
        ".swiftdoc",
        ".swiftinterface",
    ]

    public static func isScannableSourceAsset(_ path: String) -> Bool {
        let lower = path.lowercased()
        for fragment in excludedPathFragments where lower.contains(fragment.lowercased()) {
            return false
        }
        for suffix in excludedFileSuffixes where lower.hasSuffix(suffix) {
            return false
        }
        return true
    }
}
