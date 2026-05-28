import XCTest
@testable import AppSizeGuardLib

final class QuotedSubstringFalsePositiveTests: XCTestCase {
    func testUnrelatedQuotedTextDoesNotSuppressUnusedAsset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let png = root.appendingPathComponent("back.png")
        try Data(count: 4).write(to: png)

        let swift = root.appendingPathComponent("App.swift")
        try """
        import UIKit
        class App {
            func run() {
                let msg = "Welcome back to the application"
                print(msg)
            }
        }
        """.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [png.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertTrue(
            scanner.scan().contains { $0.message.contains("back") && $0.message.contains("Unused") },
            "Substring 'back' in unrelated strings must not mark back.png as referenced"
        )
    }

    func testShortQuotedLiteralsDoNotSuppressUnusedJSON() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let json = root.appendingPathComponent("DigitalHubSample.json")
        try Data("{}".utf8).write(to: json)

        let swift = root.appendingPathComponent("App.swift")
        try """
        import Foundation
        enum Keys { static let suffix = "e" }
        func demo() {
            _ = "son"
            _ = ".json"
            print(Keys.suffix)
        }
        """.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [json.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertTrue(
            scanner.scan().contains { $0.message.contains("DigitalHubSample") },
            "Single-character or extension-only quoted literals must not mark JSON as referenced"
        )
    }
}
