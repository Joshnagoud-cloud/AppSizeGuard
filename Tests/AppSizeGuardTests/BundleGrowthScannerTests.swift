import XCTest
@testable import AppSizeGuardLib

final class BundleGrowthScannerTests: XCTestCase {
    func testGrowthPercentWarning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_250_000).write(to: app.appendingPathComponent("payload.dat"))

        let baselineURL = root.appendingPathComponent(".appsizeguard-baseline.json")
        let baseline: [String: Any] = [
            "Debug": [
                "build_date": "2020-01-01T00:00:00Z",
                "app_version": "1.0",
                "total_mb": 1.0,
                "breakdown": [
                    "resources_mb": 0, "frameworks_mb": 0, "executable_mb": 0, "other_mb": 0,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: baseline)
        try data.write(to: baselineURL)

        let args = Arguments(
            projectDir: root.path,
            targetName: "Test",
            configuration: "Debug",
            builtProductsDir: root.path,
            productName: "Test.app",
            srcroot: root.path,
            updateBaseline: false
        )
        let context = try BuildContext(arguments: args)
        let scanner = BundleGrowthScanner(context: context, config: .defaults)
        let diagnostics = scanner.scan()
        XCTAssertTrue(diagnostics.contains { $0.severity == .warning || $0.severity == .error })
    }

    func testUnseededBaselineMessage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let app = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        let baselineURL = root.appendingPathComponent(".appsizeguard-baseline.json")
        let baseline: [String: Any] = [
            "Debug": [
                "build_date": "2020-01-01T00:00:00Z",
                "app_version": "1.0",
                "total_mb": 0,
                "breakdown": [
                    "resources_mb": 0, "frameworks_mb": 0, "executable_mb": 0, "other_mb": 0,
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: baseline).write(to: baselineURL)

        let context = try BuildContext(arguments: Arguments(
            projectDir: root.path, targetName: "Test", configuration: "Debug",
            builtProductsDir: root.path, productName: "Test.app", srcroot: root.path,
            updateBaseline: false
        ))
        let diagnostics = BundleGrowthScanner(context: context, config: .defaults).scan()
        XCTAssertTrue(diagnostics.contains { $0.message.contains("total_mb") })
    }
}
