import Foundation
import Darwin

public struct UnusedResourcesScanner {
    public let config: AppSizeGuardConfig
    public let resourcePaths: [String]
    public let sourcePaths: [String]
    public let srcroot: String

    private let excludedNames = Set([
        "LaunchScreen", "AppIcon", "AccentColor", "Contents",
    ])

    public func scan() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        var extractor = ResourceReferenceExtractor()

        let scannableResources = resourcePaths.filter { SourceAssetFilter.isScannableSourceAsset($0) }
        let scannableSources = sourcePaths.filter { SourceAssetFilter.isScannableSourceAsset($0) }

        // Reference extraction from sources and Interface Builder only. Do not ingest .xcassets
        // catalogs from resources — that registers every imageset/colorset as "referenced" and
        // suppresses all unused-asset warnings inside asset catalogs.
        let ingestPaths = Array(Set(scannableSources + scannableResources.filter { path in
            let ext = (path as NSString).pathExtension.lowercased()
            return ext == "storyboard" || ext == "xib"
        }))
        extractor.ingest(paths: ingestPaths)
        extractor.ingestSwiftSourcesForQuotedLiterals(scannableSources)
        extractor.ingestPropertyLists(paths: scannableResources)

        let searchableCodeFiles = loadSearchableCodeFiles(
            sourcePaths: scannableSources,
            resourcePaths: scannableResources
        )
        let searchableCodeContents = loadFileContents(at: searchableCodeFiles)
        let assetCatalogs = assetCatalogPaths(from: scannableResources)
        for catalogPath in assetCatalogs {
            diagnostics.append(contentsOf: scanImagesets(
                inCatalog: catalogPath,
                searchableCodeContents: searchableCodeContents
            ))
        }

        let checkableExts = Set([
            "png", "jpg", "jpeg", "gif", "pdf", "json", "mp4", "mov", "m4a", "wav", "mp3", "aac",
            "ttf", "otf", "zip", "html",
        ])

        for path in scannableResources {
            let ext = (path as NSString).pathExtension.lowercased()

            if ext == "xcassets" { continue }

            guard checkableExts.contains(ext) else { continue }
            if path.hasSuffix("Contents.json") && path.contains(".xcassets/") { continue }

            // Imagesets are validated when each .xcassets catalog is scanned.
            if path.contains(".imageset/") { continue }

            if path.contains(".xcassets/") {
                continue
            }

            let base = extractor.resourceBaseName(for: path)
            if excludedNames.contains(base) { continue }
            if !extractor.isReferenced(path: path) {
                let label = extractor.resourceLabel(for: path)
                diagnostics.append(unusedDiagnostic(path: path, label: label))
            }
        }

        diagnostics.append(contentsOf: scanEnvironmentSpecificZips(resources: scannableResources))

        return diagnostics
    }

    private static let searchableCodeExtensions = Set(["swift", "m", "mm", "xib", "storyboard"])

    private func loadSearchableCodeFiles(sourcePaths: [String], resourcePaths: [String]) -> [String] {
        let candidates = Array(Set(sourcePaths + resourcePaths))
        return candidates.filter { path in
            guard SourceAssetFilter.isScannableSourceAsset(path) else { return false }
            guard FileManager.default.fileExists(atPath: path) else { return false }
            let ext = (path as NSString).pathExtension.lowercased()
            guard Self.searchableCodeExtensions.contains(ext) else { return false }
            if path.contains(".xcassets/") { return false }
            return true
        }.sorted()
    }

    private func assetCatalogPaths(from paths: [String]) -> [String] {
        var catalogs = Set<String>()
        for path in paths {
            if path.hasSuffix(".xcassets"), FileManager.default.fileExists(atPath: path) {
                catalogs.insert(path)
            }
            if let range = path.range(of: ".xcassets") {
                let catalog = String(path[path.startIndex..<range.upperBound])
                if FileManager.default.fileExists(atPath: catalog) {
                    catalogs.insert(catalog)
                }
            }
        }
        return catalogs.sorted()
    }

    private func loadFileContents(at paths: [String]) -> [String] {
        paths.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
    }

    private func isImageNameUsedInCode(_ name: String, searchableCodeContents: [String]) -> Bool {
        searchableCodeContents.contains { $0.contains(name) }
    }

    private func scanImagesets(inCatalog catalogPath: String, searchableCodeContents: [String]) -> [Diagnostic] {
        let catalogName = ((catalogPath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        if excludedNames.contains(catalogName) { return [] }

        var diagnostics: [Diagnostic] = []
        for (name, imagesetPath) in listImagesets(inCatalog: catalogPath) {
            if excludedNames.contains(name) { continue }
            if isImageNameUsedInCode(name, searchableCodeContents: searchableCodeContents) { continue }
            diagnostics.append(Diagnostic(
                severity: .warning,
                category: .unused,
                path: imagesetPath,
                message: "Image '\(name)' may be unused"
            ))
        }
        return diagnostics
    }

    private func listImagesets(inCatalog catalogPath: String) -> [(name: String, path: String)] {
        var results: [(name: String, path: String)] = []
        guard let enumerator = FileManager.default.enumerator(atPath: catalogPath) else { return [] }
        for case let item as String in enumerator {
            guard item.hasSuffix(".imageset") else { continue }
            let component = (item as NSString).lastPathComponent
            let setName = (component as NSString).deletingPathExtension
            guard !setName.isEmpty else { continue }
            let fullPath = (catalogPath as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            results.append((setName, fullPath))
        }
        return results
    }

    private func unusedDiagnostic(path: String, label: (kind: String, name: String)) -> Diagnostic {
        Diagnostic(
            severity: .warning,
            category: .unused,
            path: path,
            message: "Unused \(label.kind): '\(label.name)' — not referenced in Swift, storyboards, or XIBs"
        )
    }

    /// Flags ZIPs that should not ship in the current build flavor (per §5.2 staging/production bundle rules).
    private func scanEnvironmentSpecificZips(resources: [String]) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let productionZipPatterns = ["*production*", "appinit_production.zip"]

        for path in resources {
            let name = (path as NSString).lastPathComponent
            let lower = name.lowercased()
            guard lower.hasSuffix(".zip") else { continue }

            if config.isProduction {
                guard matchesZipPatterns(lower, patterns: config.stagingZipPatterns)
                    || lower.contains("staging") else { continue }
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    category: .unused,
                    path: path,
                    message: "Staging ZIP '\(name)' is in the production target — remove from Copy Bundle Resources or use a staging build configuration"
                ))
            } else {
                guard matchesZipPatterns(lower, patterns: productionZipPatterns)
                    || lower.contains("production") else { continue }
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    category: .unused,
                    path: path,
                    message: "Production ZIP '\(name)' is in the staging target — remove from Copy Bundle Resources or use a production build configuration"
                ))
            }
        }
        return diagnostics
    }

    private func matchesZipPatterns(_ fileName: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            fnmatch(pattern, fileName, 0) == 0
                || fileName.contains(pattern.replacingOccurrences(of: "*", with: ""))
        }
    }
}

private func fnmatch(_ pattern: String, _ string: String, _ flags: Int32) -> Int32 {
    pattern.withCString { patPtr in
        string.withCString { strPtr in
            Darwin.fnmatch(patPtr, strPtr, flags)
        }
    }
}
