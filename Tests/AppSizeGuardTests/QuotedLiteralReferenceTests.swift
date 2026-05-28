import XCTest
@testable import AppSizeGuardLib

final class QuotedLiteralReferenceTests: XCTestCase {
    func testBundlePathForResourceWithExtension() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle_\(UUID().uuidString).swift")
        try """
        let path = Bundle.main.path(forResource: "config", withExtension: "json")
        """.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingestSwiftSourcesForQuotedLiterals([file.path])
        XCTAssertTrue(extractor.isReferenced(path: "/res/config.json"))
    }

    func testFileNameParameterRegistersJSON() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("filename_\(UUID().uuidString).swift")
        try #"let data = Loader.readJSON(fileName: "billing_config")"#.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingest(paths: [file.path])
        XCTAssertTrue(extractor.isReferenced(path: "/res/billing_config.json"))
    }

    func testPathLiteralMatchesNestedResource() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("nested_\(UUID().uuidString).swift")
        try #"let path = "Animations/success_trans.json""#.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingest(paths: [file.path])
        XCTAssertTrue(extractor.isReferenced(path: "/App/Resources/Animations/success_trans.json"))
    }

    func testPlistStringReferencesJSON() throws {
        var extractor = ResourceReferenceExtractor()
        let plist = FileManager.default.temporaryDirectory
            .appendingPathComponent("refs_\(UUID().uuidString).plist")
        let dict: [String: Any] = ["LaunchConfig": "success_trans"]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plist)
        defer { try? FileManager.default.removeItem(at: plist) }
        extractor.ingestPropertyLists(paths: [plist.path])
        XCTAssertTrue(extractor.isReferenced(path: "/res/success_trans.json"))
    }

    func testContentsJSONInsideImagesetNotUnused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = root.appendingPathComponent("Assets.xcassets/icon.imageset/Contents.json")
        try FileManager.default.createDirectory(at: contents.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"images":[{"filename":"icon.pdf"}]}"#.write(to: contents, atomically: true, encoding: .utf8)
        let swift = root.appendingPathComponent("App.swift")
        try #"let _ = UIImage(named: "icon")"#.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [contents.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertFalse(scanner.scan().contains { $0.path == contents.path })
    }

    func testCustomHelperQuotedFileName() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("helper_\(UUID().uuidString).swift")
        try #"let data = Utils.readJSONFromFile(fileName: "success_trans")"#.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingestSwiftSourcesForQuotedLiterals([file.path])
        XCTAssertTrue(extractor.isReferenced(path: "/res/success_trans.json"))
    }

    func testOversizedPDFInsideImageset() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pdf = dir.appendingPathComponent("Assets.xcassets/icon.imageset/icon.pdf")
        try FileManager.default.createDirectory(at: pdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0xAB, count: 600 * 1024).write(to: pdf)

        let scanner = OversizedAssetsScanner(config: .defaults, resourcePaths: [pdf.path])
        let diagnostic = try XCTUnwrap(scanner.scan().first)
        XCTAssertTrue(diagnostic.message.contains("PDF"))
        XCTAssertTrue(diagnostic.message.contains("'icon'"))
        XCTAssertFalse(diagnostic.message.contains("icon.pdf"))
    }
}
