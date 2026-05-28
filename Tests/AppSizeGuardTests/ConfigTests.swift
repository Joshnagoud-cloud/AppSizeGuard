import XCTest
@testable import AppSizeGuardLib

final class ConfigTests: XCTestCase {
    func testDefaults() {
        let config = AppSizeGuardConfig.defaults
        XCTAssertTrue(config.isProduction)
        XCTAssertEqual(config.dependencyWarnSizeMB, 10)
        XCTAssertEqual(config.spmDependencyWarnSizeMB, 3)
        XCTAssertEqual(config.growthWarnPercent, 5)
        XCTAssertEqual(config.threshold(forExtension: "png").warnKB, 500)
    }

    func testLoadYAML() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "sample.appsizeguard", withExtension: "yml")
                ?? Bundle.module.url(forResource: "sample", withExtension: "appsizeguard.yml", subdirectory: "Fixtures")
        )
        let config = try AppSizeGuardConfig.load(from: url)
        XCTAssertTrue(config.isProduction)
        XCTAssertEqual(config.dependencyWarnSizeMB, 10)
        XCTAssertEqual(config.spmDependencyWarnSizeMB, 3)
    }
}
