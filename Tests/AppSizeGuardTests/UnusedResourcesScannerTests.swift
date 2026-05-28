import XCTest
@testable import AppSizeGuardLib

final class UnusedResourcesScannerTests: XCTestCase {
    func testSkipsPNGsInsideFramework() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let framework = root.appendingPathComponent("SDK.framework/Resources")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let png = framework.appendingPathComponent("glyph.png")
        try Data(count: 4).write(to: png)

        let swift = root.appendingPathComponent("App.swift")
        try #"let _ = UIImage(named: "used")"#.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [png.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertTrue(scanner.scan().isEmpty)
    }

    func testPDFInImagesetNotUnusedWhenImagesetReferenced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let imageset = root.appendingPathComponent("Assets.xcassets/icon.imageset")
        try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pdf = imageset.appendingPathComponent("icon.pdf")
        try Data(count: 4).write(to: pdf)

        let swift = root.appendingPathComponent("App.swift")
        try #"let _ = UIImage(named: "icon")"#.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [pdf.path, imageset.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets.xcassets").path],
            sourcePaths: [swift.path, imageset.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets.xcassets").path],
            srcroot: root.path
        )
        XCTAssertFalse(scanner.scan().contains { $0.message.contains("icon") && $0.message.contains("may be unused") })
    }

    func testImagesetReferencedFromStoryboard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let catalog = root.appendingPathComponent("Assets.xcassets")
        let imageset = catalog.appendingPathComponent("tab_home.imageset")
        try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(count: 4).write(to: imageset.appendingPathComponent("tab_home.png"))

        let storyboard = root.appendingPathComponent("Main.storyboard")
        try """
        <document>
            <image name="tab_home" width="24" height="24"/>
        </document>
        """.write(to: storyboard, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [catalog.path, storyboard.path],
            sourcePaths: [],
            srcroot: root.path
        )
        XCTAssertFalse(scanner.scan().contains { $0.message.contains("tab_home") && $0.message.contains("may be unused") })
    }

    func testImagesetFoundByPlainTextInComment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let catalog = root.appendingPathComponent("Assets.xcassets")
        let imageset = catalog.appendingPathComponent("referenced_in_comment.imageset")
        try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(count: 4).write(to: imageset.appendingPathComponent("referenced_in_comment.png"))

        let swift = root.appendingPathComponent("App.swift")
        try """
        // TODO: wire up referenced_in_comment asset
        func load(icon: String) {
            _ = UIImage(named: icon)
        }
        """.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [catalog.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertFalse(scanner.scan().contains { $0.message.contains("referenced_in_comment") && $0.message.contains("may be unused") })
    }

    func testImagesetScannedWhenOnlyInnerAssetPathInResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let catalog = root.appendingPathComponent("Assets.xcassets")
        let imageset = catalog.appendingPathComponent("inner_only_orphan.imageset")
        try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let png = imageset.appendingPathComponent("inner_only_orphan.png")
        try Data(count: 4).write(to: png)

        let swift = root.appendingPathComponent("App.swift")
        try #"print("ok")"#.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [png.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertTrue(scanner.scan().contains { $0.message.contains("inner_only_orphan") && $0.message.contains("may be unused") })
    }

    func testUnusedImagesetReportedWhenNotReferenced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let catalog = root.appendingPathComponent("Assets.xcassets")
        let imageset = catalog.appendingPathComponent("orphan_icon.imageset")
        try FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let png = imageset.appendingPathComponent("orphan_icon.png")
        try Data(count: 4).write(to: png)

        let swift = root.appendingPathComponent("App.swift")
        try #"let _ = UIImage(named: "used_only")"#.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [png.path, catalog.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertTrue(scanner.scan().contains { $0.message.contains("orphan_icon") && $0.message.contains("may be unused") })
    }

    func testUnusedStandalonePNGReportedWhenNotReferenced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let png = root.appendingPathComponent("orphan_banner.png")
        try Data(count: 4).write(to: png)

        let swift = root.appendingPathComponent("App.swift")
        try #"print("hello")"#.write(to: swift, atomically: true, encoding: .utf8)

        let scanner = UnusedResourcesScanner(
            config: .defaults,
            resourcePaths: [png.path],
            sourcePaths: [swift.path],
            srcroot: root.path
        )
        XCTAssertTrue(scanner.scan().contains { $0.message.contains("orphan_banner") && $0.message.contains("Unused") })
    }
}
