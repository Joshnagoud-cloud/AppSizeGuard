// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppSizeGuard",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "appsizeguard", targets: ["AppSizeGuard"]),
        .plugin(name: "AppSizeGuardPlugin", targets: ["AppSizeGuardPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "AppSizeGuardLib",
            dependencies: ["Yams"],
            path: "Sources/AppSizeGuardLib"
        ),
        .executableTarget(
            name: "AppSizeGuard",
            dependencies: ["AppSizeGuardLib"],
            path: "Sources/AppSizeGuard"
        ),
        .plugin(
            name: "AppSizeGuardPlugin",
            capability: .buildTool(),
            dependencies: ["AppSizeGuard"],
            path: "Plugins/AppSizeGuardPlugin"
        ),
        .testTarget(
            name: "AppSizeGuardTests",
            dependencies: ["AppSizeGuardLib"],
            path: "Tests/AppSizeGuardTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
