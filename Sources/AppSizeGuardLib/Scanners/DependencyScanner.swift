import Foundation

public struct DependencyScanner {
    public let config: AppSizeGuardConfig
    public let srcroot: String
    public let projectDir: String
    public let builtProductsDir: String

    public init(config: AppSizeGuardConfig, srcroot: String, projectDir: String, builtProductsDir: String = "") {
        self.config = config
        self.srcroot = srcroot
        self.projectDir = projectDir
        self.builtProductsDir = builtProductsDir
    }

    public func scan() -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let warnBytes = Int64(config.dependencyWarnSizeMB) * 1024 * 1024

        diagnostics.append(contentsOf: scanCocoaPods(warnBytes: warnBytes))
        let spmWarnBytes = Int64(config.spmDependencyWarnSizeMB) * 1024 * 1024
        diagnostics.append(contentsOf: scanSPM(warnBytes: spmWarnBytes))
        return diagnostics
    }

    private func scanCocoaPods(warnBytes: Int64) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let lockCandidates = [
            (srcroot as NSString).appendingPathComponent("Podfile.lock"),
            (projectDir as NSString).appendingPathComponent("Podfile.lock"),
        ]
        guard let lockPath = lockCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return diagnostics
        }

        let podsCandidates = [
            (srcroot as NSString).appendingPathComponent("Pods"),
            (projectDir as NSString).appendingPathComponent("Pods"),
        ]
        guard let podsDir = podsCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return diagnostics
        }

        guard let content = try? String(contentsOfFile: lockPath, encoding: .utf8) else { return diagnostics }
        let podNames = parsePodNames(from: content)

        for pod in podNames {
            let podPath = (podsDir as NSString).appendingPathComponent(pod)
            guard FileManager.default.fileExists(atPath: podPath) else { continue }
            let size = podDirectorySize(at: podPath)
            guard size >= warnBytes else { continue }
            let formatted = formatBytes(size)
            diagnostics.append(Diagnostic(
                severity: .warning,
                category: .dependencies,
                path: podPath,
                message: "CocoaPods '\(pod)' — \(formatted) (exceeds \(config.dependencyWarnSizeMB)MB threshold)"
            ))
        }
        return diagnostics
    }

    private func scanSPM(warnBytes: Int64) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        guard let resolvedPath = findPackageResolved() else { return diagnostics }

        let packages = parseResolvedPackages(from: resolvedPath)
        let checkoutRoots = findCheckoutRoots()

        for package in packages {
            guard let checkoutPath = findCheckout(for: package, in: checkoutRoots) else {
                continue
            }
            let size = DirectoryWalker.directorySize(at: checkoutPath)
            guard size >= warnBytes else { continue }
            let formatted = formatBytes(size)
            diagnostics.append(Diagnostic(
                severity: .warning,
                category: .dependencies,
                path: checkoutPath,
                message: "SwiftPM '\(package.displayName)' — \(formatted) (exceeds \(config.spmDependencyWarnSizeMB)MB threshold)"
            ))
        }
        return diagnostics
    }

    private func findPackageResolved() -> String? {
        var candidates = [
            (srcroot as NSString).appendingPathComponent("Package.resolved"),
            (projectDir as NSString).appendingPathComponent("Package.resolved"),
        ]
        candidates.append(contentsOf: findFiles(named: "Package.resolved", under: projectDir, maxDepth: 8))
        candidates.append(contentsOf: findFiles(named: "Package.resolved", under: srcroot, maxDepth: 8))
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func findCheckoutRoots() -> [String] {
        var roots = [
            (srcroot as NSString).appendingPathComponent("SourcePackages/checkouts"),
            (projectDir as NSString).appendingPathComponent("SourcePackages/checkouts"),
            (srcroot as NSString).appendingPathComponent(".build/checkouts"),
        ]
        if let derivedCheckouts = sourcePackagesCheckoutsNearBuildProducts() {
            roots.append(derivedCheckouts)
        }
        roots.append(contentsOf: findDirectories(named: "checkouts", under: projectDir, maxDepth: 10))
        roots.append(contentsOf: findDirectories(named: "checkouts", under: srcroot, maxDepth: 10))
        return Array(Set(roots)).filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Resolves `DerivedData/.../SourcePackages/checkouts` from Xcode's `BUILT_PRODUCTS_DIR`.
    private func sourcePackagesCheckoutsNearBuildProducts() -> String? {
        guard !builtProductsDir.isEmpty else { return nil }
        var url = URL(fileURLWithPath: builtProductsDir).standardizedFileURL
        // .../Build/Products/Debug-iphoneos
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        let checkouts = url.appendingPathComponent("SourcePackages/checkouts")
        let path = checkouts.path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return path
        }
        return nil
    }

    private func findFiles(named fileName: String, under root: String, maxDepth: Int) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: root) else { return [] }
        var results: [String] = []
        let rootDepth = (root as NSString).pathComponents.count
        for case let item as String in enumerator {
            let full = (root as NSString).appendingPathComponent(item)
            let depth = (full as NSString).pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if (item as NSString).lastPathComponent == fileName {
                results.append(full)
            }
        }
        return results
    }

    private func findDirectories(named dirName: String, under root: String, maxDepth: Int) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: root) else { return [] }
        var results: [String] = []
        let rootDepth = (root as NSString).pathComponents.count
        for case let item as String in enumerator {
            let full = (root as NSString).appendingPathComponent(item)
            let depth = (full as NSString).pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue,
               (item as NSString).lastPathComponent == dirName {
                results.append(full)
            }
        }
        return results
    }

    private func podDirectorySize(at podPath: String) -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: podPath) else {
            return DirectoryWalker.directorySize(at: podPath)
        }
        var total: Int64 = 0
        for item in items where !item.hasSuffix(".framework") {
            let path = (podPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                total += DirectoryWalker.directorySize(at: path)
            } else {
                total += DirectoryWalker.fileSize(at: path) ?? 0
            }
        }
        return total
    }

    private struct ResolvedPackage {
        let identity: String
        let displayName: String
    }

    private func parseResolvedPackages(from path: String) -> [ResolvedPackage] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pins = json["pins"] as? [[String: Any]] else { return [] }

        return pins.compactMap { pin in
            guard let identity = pin["identity"] as? String else { return nil }
            let name = (pin["location"] as? String)
                .flatMap { URL(string: $0)?.lastPathComponent.replacingOccurrences(of: ".git", with: "") }
                ?? identity
            return ResolvedPackage(identity: identity, displayName: name)
        }
    }

    private func findCheckout(for package: ResolvedPackage, in roots: [String]) -> String? {
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            if let exact = items.first(where: { $0 == package.identity || $0.hasPrefix(package.identity + "-") }) {
                return (root as NSString).appendingPathComponent(exact)
            }
            if let byName = items.first(where: { $0.lowercased().contains(package.displayName.lowercased()) }) {
                return (root as NSString).appendingPathComponent(byName)
            }
        }
        return nil
    }

    private func parsePodNames(from lockContent: String) -> [String] {
        var names: [String] = []
        var inPods = false
        for line in lockContent.components(separatedBy: .newlines) {
            if line == "PODS:" { inPods = true; continue }
            if line.hasPrefix("DEPENDENCIES:") { break }
            guard inPods else { continue }
            if line.hasPrefix("  - ") {
                let podLine = String(line.dropFirst(4))
                let name = podLine.split(separator: " (").first.map(String.init) ?? podLine
                if !name.isEmpty, !name.hasPrefix("Pods-") { names.append(name) }
            }
        }
        return names
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
