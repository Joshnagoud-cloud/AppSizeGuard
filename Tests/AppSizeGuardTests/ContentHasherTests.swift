import XCTest
@testable import AppSizeGuardLib

final class ContentHasherTests: XCTestCase {
    func testNormalizedBaseNameStripsScale() {
        XCTAssertEqual(ContentHasher.normalizedBaseName(for: "/a/icon@2x.png"), "icon")
        XCTAssertEqual(ContentHasher.normalizedBaseName(for: "/a/icon@3x.png"), "icon")
        XCTAssertEqual(ContentHasher.normalizedBaseName(for: "/a/icon.png"), "icon")
    }
}
