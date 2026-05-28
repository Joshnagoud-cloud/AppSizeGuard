// Plugins/AppSizeGuardPlugin/plugin.swift
import PackagePlugin

@main
struct AppSizeGuardPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let tool = try context.tool(named: "appsizeguard")
        return [
            .prebuildCommand(
                displayName: "AppSizeGuard",
                executable: tool.path,
                arguments: [
                    "--project-dir", context.package.directory.string,
                    "--target", target.name,
                    "--srcroot", context.package.directory.string
                ],
                outputFilesDirectory: context.pluginWorkDirectory
            )
        ]
    }
}
