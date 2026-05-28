import Foundation

public enum BuildContextError: LocalizedError {
    case missingTargetName

    public var errorDescription: String? {
        switch self {
        case .missingTargetName:
            return "TARGET_NAME is empty; run AppSizeGuard from an Xcode Run Script build phase."
        }
    }
}

public struct BuildContext {
    public let projectDir: String
    public let targetName: String
    public let configuration: String
    public let builtProductsDir: String
    public let productName: String
    public let srcroot: String
    public let configURL: URL
    public let baselineURL: URL
    public let shouldUpdateBaseline: Bool
    public let isDebug: Bool

    public var appBundlePath: String? {
        guard !builtProductsDir.isEmpty, !productName.isEmpty else { return nil }
        let path = (builtProductsDir as NSString).appendingPathComponent(productName)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return path
        }
        return nil
    }

    public init(arguments: Arguments) throws {
        guard !arguments.targetName.isEmpty else {
            throw BuildContextError.missingTargetName
        }
        projectDir = (arguments.projectDir as NSString).standardizingPath
        targetName = arguments.targetName
        configuration = arguments.configuration
        builtProductsDir = arguments.builtProductsDir
        productName = arguments.productName
        srcroot = (arguments.srcroot as NSString).standardizingPath
        configURL = URL(fileURLWithPath: srcroot).appendingPathComponent(".appsizeguard.yml")
        baselineURL = URL(fileURLWithPath: srcroot).appendingPathComponent(".appsizeguard-baseline.json")
        shouldUpdateBaseline = arguments.updateBaseline
        isDebug = configuration == "Debug"
    }
}
