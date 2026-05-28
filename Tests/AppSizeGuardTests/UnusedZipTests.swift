import XCTest
@testable import AppSizeGuardLib

final class UnusedZipTests: XCTestCase {
    func testUnusedZipDetectedInMainLoop() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let zip = root.appendingPathComponent("orphan_data.zip")
        try Data(count: 4).write(to: zip)
        let swift = root.appendingPathComponent("App.swift")
        try #"print("hello")"#.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [zip.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertTrue(scanner.scan().contains { $0.message.contains("orphan_data.zip") })
    }

    func testProductionBuildFlagsStagingZipInBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let zip = root.appendingPathComponent("appinit_staging.zip")
        try Data(count: 4).write(to: zip)
        let swift = root.appendingPathComponent("App.swift")
        try #"let name = "appinit_staging.zip""#.write(to: swift, atomically: true, encoding: .utf8)

        var config = AppSizeGuardConfig.defaults
        config.isProduction = true

        let scanner = UnusedResourcesScanner(
            config: config,
            resourcePaths: [zip.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        let messages = scanner.scan().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("appinit_staging.zip") && $0.contains("production target") })
    }

    func testStagingBuildFlagsProductionZipInBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let zip = root.appendingPathComponent("appinit_production.zip")
        try Data(count: 4).write(to: zip)
        let swift = root.appendingPathComponent("App.swift")
        try #"let name = "appinit_production.zip""#.write(to: swift, atomically: true, encoding: .utf8)

        var config = AppSizeGuardConfig.defaults
        config.isProduction = false

        let scanner = UnusedResourcesScanner(
            config: config,
            resourcePaths: [zip.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        let messages = scanner.scan().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("appinit_production.zip") && $0.contains("staging target") })
    }
}
