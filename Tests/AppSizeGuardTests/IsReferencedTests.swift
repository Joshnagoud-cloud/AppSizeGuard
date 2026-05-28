import XCTest
@testable import AppSizeGuardLib

final class IsReferencedTests: XCTestCase {
    func testShortQuotedLiteralDoesNotMarkUnrelatedFiles() throws {
        var extractor = ResourceReferenceExtractor()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("short_\(UUID().uuidString).swift")
        try #"let x = "a""#.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        extractor.ingestSwiftSourcesForQuotedLiterals([file.path])
        XCTAssertFalse(extractor.isReferenced(path: "/res/notification.json"))
        XCTAssertFalse(extractor.isReferenced(path: "/res/icon.pdf"))
    }

    func testUnusedJSONDetectedWhenNotQuoted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let json = root.appendingPathComponent("orphan_data.json")
        try Data(count: 4).write(to: json)
        let swift = root.appendingPathComponent("App.swift")
        try #"print("hello")"#.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [json.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertTrue(scanner.scan().contains { $0.message.contains("orphan_data.json") })
    }
}
