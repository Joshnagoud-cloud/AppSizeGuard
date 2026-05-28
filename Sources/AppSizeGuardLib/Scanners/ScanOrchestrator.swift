import Foundation

public struct ScanOrchestrator {
    public let context: BuildContext
    public let config: AppSizeGuardConfig
    public let project: ProjectIndex
    public let reporter: XcodeDiagnosticReporter

    public func run() {
        if project.resourcePaths.isEmpty {
            reporter.emit(Diagnostic(
                severity: .note,
                category: .general,
                path: project.pbxprojPath,
                message: "No resources resolved for target '\(context.targetName)'; oversized/unused asset scans skipped (check Copy Bundle Resources and SRCROOT paths)"
            ))
        }

        runScanner(name: "OversizedAssets") {
            OversizedAssetsScanner(config: config, resourcePaths: assetResourcePaths())
                .scan()
        }
        runScanner(name: "DuplicateAssets") {
            DuplicateAssetsScanner(resourcePaths: assetResourcePaths(), reporter: reporter).scan()
        }
        runScanner(name: "UnusedResources") {
            UnusedResourcesScanner(
                config: config,
                resourcePaths: project.resourcePaths,
                sourcePaths: project.sourcePaths,
                srcroot: context.srcroot
            ).scan()
        }
        runScanner(name: "Dependencies") {
            DependencyScanner(
                config: config,
                srcroot: context.srcroot,
                projectDir: context.projectDir,
                builtProductsDir: context.builtProductsDir
            ).scan()
        }
        runScanner(name: "EmbeddedFrameworks") {
            EmbeddedFrameworkScanner(context: context, config: config).scan()
        }
        runScanner(name: "BundleGrowth") {
            BundleGrowthScanner(context: context, config: config).scan()
        }
    }

    private func assetResourcePaths() -> [String] {
        project.resourcePaths.filter { path in
            !path.contains(".car") && SourceAssetFilter.isScannableSourceAsset(path)
        }
    }

    private func runScanner(name: String, _ block: () throws -> [Diagnostic]) {
        do {
            let results = try block()
            reporter.emitAll(results)
        } catch {
            reporter.emit(Diagnostic(
                severity: .note,
                category: .general,
                path: project.pbxprojPath,
                message: "\(name) scanner failed: \(error.localizedDescription)"
            ))
        }
    }
}
