import Foundation

public enum AppSizeGuardCLI {
    public static func run() {
        let args = Arguments.parse(CommandLine.arguments)
        let reporter = XcodeDiagnosticReporter()

        do {
            let context = try BuildContext(arguments: args)
            let config = try AppSizeGuardConfig.load(from: context.configURL)
            let project = try PBXProjParser(
                projectDir: context.projectDir,
                srcroot: context.srcroot
            ).parse(targetName: context.targetName)

            ScanOrchestrator(context: context, config: config, project: project, reporter: reporter).run()
        } catch let error as BuildContextError {
            reporter.emit(Diagnostic(
                severity: .note,
                category: .general,
                path: args.projectDir,
                message: "AppSizeGuard skipped: \(error.localizedDescription)"
            ))
        } catch {
            reporter.emit(Diagnostic(
                severity: .note,
                category: .general,
                path: args.projectDir,
                message: "AppSizeGuard failed: \(error.localizedDescription)"
            ))
        }

        exit(0)
    }
}
