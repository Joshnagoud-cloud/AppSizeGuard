// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppSizeGuard",
    platforms: [.macOS(.v13)],
    products: [
        .plugin(name: "AppSizeGuardPlugin", targets: ["AppSizeGuardPlugin"]),
    ],
    targets: [
        .binaryTarget(
            name: "AppSizeGuardBinary",
            url: "https://github.com/Joshnagoud-cloud/AppSizeGuard/releases/download/1.0.2/appsizeguard.artifactbundle.zip",
            checksum: "555fa1f68f78d47718a9ab1c2f43607d8d88c08fe79654a1efbffbbd1c8f2f19"
        ),
        .plugin(
            name: "AppSizeGuardPlugin",
            capability: .buildTool(),
            dependencies: ["AppSizeGuardBinary"],
            path: "Plugins/AppSizeGuardPlugin"
        ),
    ]
)
