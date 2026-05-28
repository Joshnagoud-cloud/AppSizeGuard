import XCTest
@testable import AppSizeGuardLib

final class ResourceReferenceExtractorTests: XCTestCase {
    func testSwiftImageNamed() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_refs_\(UUID().uuidString).swift")
        try #"let i = UIImage(named: "hero")"#.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingest(paths: [file.path])
        XCTAssertTrue(extractor.staticReferences.contains("hero"))
    }

    func testStaticAndDynamicUIImageNamedReferences() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_dynamic_\(UUID().uuidString).swift")
        try """
        let name = "hero"
        let a = UIImage(named: "static")
        let b = UIImage(named: name)
        """.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingest(paths: [file.path])
        XCTAssertTrue(extractor.staticReferences.contains("static"))
    }

    func testImagesetNameFromPath() {
        let path = "/App/Assets.xcassets/logo.imageset/logo@2x.png"
        XCTAssertEqual(ResourceReferenceExtractor().imagesetName(from: path), "logo")
    }

    func testIsImagesetNameReferenced() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("imageset_ref_\(UUID().uuidString).swift")
        try #"let _ = Image("logo")"#.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingest(paths: [file.path])
        XCTAssertTrue(extractor.isImagesetNameReferenced("logo"))
        XCTAssertFalse(extractor.isImagesetNameReferenced("missing"))
    }

    func testLottieAnimationNamed() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("lottie_\(UUID().uuidString).swift")
        try #"let anim = LottieAnimation.named("success_trans")"#.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingest(paths: [file.path])
        XCTAssertTrue(extractor.staticReferences.contains("success_trans"))
        XCTAssertTrue(extractor.staticReferences.contains("success_trans.json"))
        XCTAssertTrue(extractor.isReferenced(path: "/bundle/success_trans.json"))
    }

    func testUIImageGifName() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif_\(UUID().uuidString).swift")
        try #"let img = UIImage.gif(name: "notification")"#.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingest(paths: [file.path])
        XCTAssertTrue(extractor.staticReferences.contains("notification"))
        XCTAssertTrue(extractor.isReferenced(path: "/bundle/notification.gif"))
    }
}
