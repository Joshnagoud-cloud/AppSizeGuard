import XCTest
@testable import AppSizeGuardLib

final class DependencyScannerTests: XCTestCase {
    func testSPMWarnsAbove3MBDefault() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let checkouts = root.appendingPathComponent("SourcePackages/checkouts/heavy-pkg")
        try FileManager.default.createDirectory(at: checkouts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let blob = checkouts.appendingPathComponent("blob.bin")
        try Data(repeating: 0xFF, count: 4 * 1024 * 1024).write(to: blob)

        let resolved = root.appendingPathComponent("Package.resolved")
        let resolvedJSON: [String: Any] = [
            "pins": [
                [
                    "identity": "heavy-pkg",
                    "location": "https://github.com/example/heavy-pkg.git",
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: resolvedJSON).write(to: resolved)

        let scanner = DependencyScanner(
            config: .defaults,
            srcroot: root.path,
            projectDir: root.path
        )
        let messages = scanner.scan().map(\.message)
        XCTAssertTrue(messages.contains { $0.contains("SwiftPM") && $0.contains("heavy-pkg") })
        XCTAssertTrue(messages.contains { $0.contains("3MB threshold") })
    }

    func testSPMSilentBelow3MB() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let checkouts = root.appendingPathComponent("SourcePackages/checkouts/small-pkg")
        try FileManager.default.createDirectory(at: checkouts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let blob = checkouts.appendingPathComponent("blob.bin")
        try Data(repeating: 0xFF, count: 2 * 1024 * 1024).write(to: blob)

        let resolved = root.appendingPathComponent("Package.resolved")
        let resolvedJSON: [String: Any] = [
            "pins": [
                [
                    "identity": "small-pkg",
                    "location": "https://github.com/example/small-pkg.git",
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: resolvedJSON).write(to: resolved)

        let scanner = DependencyScanner(config: .defaults, srcroot: root.path, projectDir: root.path)
        XCTAssertFalse(scanner.scan().contains { $0.message.contains("small-pkg") })
    }
}
