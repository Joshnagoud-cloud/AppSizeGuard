import XCTest
@testable import AppSizeGuardLib

final class BaselineWriteTests: XCTestCase {
    func testBaselineNotWrittenWithoutCIEnv() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(count: 10).write(to: app.appendingPathComponent("x.dat"))

        let baselineURL = root.appendingPathComponent(".appsizeguard-baseline.json")
        let baseline: [String: Any] = [
            "Debug": [
                "build_date": "2020-01-01T00:00:00Z",
                "app_version": "1.0",
                "total_mb": 0.01,
                "breakdown": [
                    "resources_mb": 0, "frameworks_mb": 0, "executable_mb": 0, "other_mb": 0,
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: baseline).write(to: baselineURL)

        let args = Arguments(
            projectDir: root.path,
            targetName: "App",
            configuration: "Debug",
            builtProductsDir: root.path,
            productName: "App.app",
            srcroot: root.path,
            updateBaseline: false
        )
        let context = try BuildContext(arguments: args)
        XCTAssertFalse(context.shouldUpdateBaseline)
        _ = BundleGrowthScanner(context: context, config: .defaults).scan()

        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: baselineURL)) as? [String: Any]
        let debug = after?["Debug"] as? [String: Any]
        XCTAssertEqual((debug?["total_mb"] as? NSNumber)?.doubleValue, 0.01)
    }

    func testBaselineWrittenWhenUpdateBaselineEnabled() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 2 * 1024 * 1024).write(to: app.appendingPathComponent("App"))
        let plist: [String: Any] = [
            "CFBundleExecutable": "App",
            "CFBundleShortVersionString": "3.1.0",
        ]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))

        let baselineURL = root.appendingPathComponent(".appsizeguard-baseline.json")
        let placeholder: [String: Any] = [
            "Debug": [
                "build_date": "1970-01-01T00:00:00Z",
                "app_version": "0.0.0",
                "total_mb": 0,
                "breakdown": [
                    "resources_mb": 0, "frameworks_mb": 0, "executable_mb": 0, "other_mb": 0,
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: placeholder).write(to: baselineURL)

        let args = Arguments(
            projectDir: root.path,
            targetName: "App",
            configuration: "Debug",
            builtProductsDir: root.path,
            productName: "App.app",
            srcroot: root.path,
            updateBaseline: true
        )
        let context = try BuildContext(arguments: args)
        XCTAssertTrue(context.shouldUpdateBaseline)
        let diagnostics = BundleGrowthScanner(context: context, config: .defaults).scan()
        XCTAssertTrue(diagnostics.contains { $0.message.contains("Baseline updated") })

        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: baselineURL)) as? [String: Any]
        let debug = after?["Debug"] as? [String: Any]
        let totalMB = (debug?["total_mb"] as? NSNumber)?.doubleValue ?? 0
        XCTAssertGreaterThan(totalMB, 0)
        XCTAssertNil(debug?["total_bytes"])
        XCTAssertEqual(debug?["app_version"] as? String, "3.1.0")
    }

    func testReadsLegacyTotalBytesBaseline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("App.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_250_000).write(to: app.appendingPathComponent("payload.dat"))

        let baselineURL = root.appendingPathComponent(".appsizeguard-baseline.json")
        let baseline: [String: Any] = [
            "Debug": [
                "build_date": "2020-01-01T00:00:00Z",
                "app_version": "1.0",
                "total_bytes": 1_048_576,
                "breakdown": ["resources": 0, "frameworks": 0, "executable": 0, "other": 0],
            ],
        ]
        try JSONSerialization.data(withJSONObject: baseline).write(to: baselineURL)

        let context = try BuildContext(arguments: Arguments(
            projectDir: root.path, targetName: "App", configuration: "Debug",
            builtProductsDir: root.path, productName: "App.app", srcroot: root.path,
            updateBaseline: false
        ))
        let diagnostics = BundleGrowthScanner(context: context, config: .defaults).scan()
        XCTAssertTrue(diagnostics.contains { $0.severity == .warning || $0.severity == .error })
    }
}
