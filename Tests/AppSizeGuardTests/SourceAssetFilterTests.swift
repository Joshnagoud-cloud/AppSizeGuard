import XCTest
@testable import AppSizeGuardLib

final class SourceAssetFilterTests: XCTestCase {
    func testExcludesFrameworkSwiftModuleABI() {
        let path = "/App/SpamDetectionFramework.framework/Modules/SpamDetectionFramework.swiftmodule/arm64-apple-ios.abi.json"
        XCTAssertFalse(SourceAssetFilter.isScannableSourceAsset(path))
    }

    func testExcludesFrameworkPNG() {
        let path = "/App/MySDK.framework/Resources/tab_icon.png"
        XCTAssertFalse(SourceAssetFilter.isScannableSourceAsset(path))
    }

    func testIncludesSourceJSON() {
        let path = "/App/Resources/success_trans.json"
        XCTAssertTrue(SourceAssetFilter.isScannableSourceAsset(path))
    }
}
