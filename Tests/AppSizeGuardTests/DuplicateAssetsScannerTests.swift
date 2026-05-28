import XCTest
@testable import AppSizeGuardLib

final class DuplicateAssetsScannerTests: XCTestCase {
    func testDetectsDuplicateContent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let data = Data([0x01, 0x02, 0x03])
        let a = dir.appendingPathComponent("a.png")
        let b = dir.appendingPathComponent("b@2x.png")
        try data.write(to: a)
        try data.write(to: b)

        let reporter = XcodeDiagnosticReporter()
        let scanner = DuplicateAssetsScanner(resourcePaths: [a.path, b.path], reporter: reporter)
        let diagnostics = scanner.scan()
        XCTAssertEqual(diagnostics.count, 1)
        XCTAssertTrue(diagnostics[0].message.contains("Duplicate"))
    }
}
