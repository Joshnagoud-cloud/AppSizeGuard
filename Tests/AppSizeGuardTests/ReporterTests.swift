import XCTest
@testable import AppSizeGuardLib

final class ReporterTests: XCTestCase {
    func testDiagnosticFormat() {
        let d = Diagnostic(
            severity: .warning,
            category: .assets,
            path: "/tmp/a.png",
            message: "test"
        )
        XCTAssertEqual(d.severity.rawValue, "warning")
        XCTAssertEqual(d.category.rawValue, "Assets")
    }
}
