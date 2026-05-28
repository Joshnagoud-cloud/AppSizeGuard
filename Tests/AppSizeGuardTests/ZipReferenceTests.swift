import XCTest
@testable import AppSizeGuardLib

final class ZipReferenceTests: XCTestCase {
    func testTernaryZipLiteralsMarkReferenced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let zip = root.appendingPathComponent("appinit_staging.zip")
        try Data(count: 1).write(to: zip)
        let swift = root.appendingPathComponent("API.swift")
        try """
        let appinit = (true) ? "appinit_production.zip" : "appinit_staging.zip"
        """.write(to: swift, atomically: true, encoding: .utf8)

        var extractor = ResourceReferenceExtractor()
        extractor.ingestSwiftSourcesForQuotedLiterals([swift.path])
        XCTAssertTrue(extractor.isReferenced(path: zip.path))
    }

    func testQuotedLiteralIndexingDoesNotSpanLines() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let swift = root.appendingPathComponent("Broken.swift")
        try """
        let broken = "start
                let appinit = (IS_PRODUCTION == "YES") ? "appinit_production.zip" : "appinit_staging.zip"
        """.write(to: swift, atomically: true, encoding: .utf8)

        var extractor = ResourceReferenceExtractor()
        extractor.ingest(paths: [swift.path])
        XCTAssertTrue(extractor.quotedStringLiterals.contains("appinit_staging.zip"))
        XCTAssertTrue(extractor.quotedStringLiterals.contains("appinit_production.zip"))
    }
}
