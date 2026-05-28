import XCTest
@testable import AppSizeGuardLib

final class OversizedAssetsScannerTests: XCTestCase {
    func testOversizedPNGWarning() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let png = dir.appendingPathComponent("big.png")
        let data = Data(repeating: 0xAB, count: 600 * 1024)
        try data.write(to: png)

        let scanner = OversizedAssetsScanner(config: .defaults, resourcePaths: [png.path])
        let diagnostics = scanner.scan()
        XCTAssertFalse(diagnostics.isEmpty)
        XCTAssertEqual(diagnostics.first?.category, .assets)
        XCTAssertEqual(diagnostics.first?.severity, .warning)
    }

    func testExceedingErrorThresholdStillWarning() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let json = dir.appendingPathComponent("large.json")
        try Data(repeating: 0xAB, count: 1100 * 1024).write(to: json)

        let scanner = OversizedAssetsScanner(config: .defaults, resourcePaths: [json.path])
        let diagnostics = scanner.scan()
        XCTAssertEqual(diagnostics.first?.severity, .warning)
    }

    func testSkipsFrameworkABIJson() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = dir
            .appendingPathComponent("Foo.framework/Modules/Foo.swiftmodule")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let abi = nested.appendingPathComponent("arm64-apple-ios.abi.json")
        try Data(repeating: 0xAB, count: 1100 * 1024).write(to: abi)

        let scanner = OversizedAssetsScanner(config: .defaults, resourcePaths: [abi.path])
        XCTAssertTrue(scanner.scan().isEmpty)
    }
}
