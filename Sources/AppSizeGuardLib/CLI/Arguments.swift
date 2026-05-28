import Foundation

public struct Arguments: Equatable {
    public let projectDir: String
    public let targetName: String
    public let configuration: String
    public let builtProductsDir: String
    public let productName: String
    public let srcroot: String
    public let updateBaseline: Bool

    public static func parse(_ argv: [String]) -> Arguments {
        var map: [String: String] = [:]
        var updateBaseline = false
        var i = 1
        while i < argv.count {
            let key = argv[i]
            if key == "--update-baseline" {
                updateBaseline = true
                i += 1
            } else if key.hasPrefix("--"), i + 1 < argv.count {
                map[String(key.dropFirst(2))] = argv[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        let env = ProcessInfo.processInfo.environment
        if env["APPSIZEGUARD_UPDATE_BASELINE"] == "1" {
            updateBaseline = true
        }

        return Arguments(
            projectDir: map["project-dir"] ?? env["PROJECT_DIR"] ?? ".",
            targetName: map["target"] ?? env["TARGET_NAME"] ?? "",
            configuration: map["configuration"] ?? env["CONFIGURATION"] ?? "Debug",
            builtProductsDir: map["built-products-dir"] ?? env["BUILT_PRODUCTS_DIR"] ?? "",
            productName: map["product-name"] ?? env["FULL_PRODUCT_NAME"] ?? "",
            srcroot: map["srcroot"] ?? env["SRCROOT"] ?? ".",
            updateBaseline: updateBaseline
        )
    }
}
