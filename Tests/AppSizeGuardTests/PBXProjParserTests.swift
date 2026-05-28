import XCTest
@testable import AppSizeGuardLib

final class PBXProjParserTests: XCTestCase {
    func testResolvesSOURCE_ROOTResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let srcroot = root.appendingPathComponent("App")
        let xcodeproj = root.appendingPathComponent("Sample.xcodeproj")
        try FileManager.default.createDirectory(at: srcroot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data().write(to: srcroot.appendingPathComponent("hero.png"))
        try Data().write(to: srcroot.appendingPathComponent("AppDelegate.swift"))

        let fixture = try XCTUnwrap(
            Bundle.module.url(forResource: "minimal", withExtension: "pbxproj", subdirectory: "Fixtures")
                ?? Bundle.module.url(forResource: "minimal.pbxproj", withExtension: nil)
        )
        let pbxDest = xcodeproj.appendingPathComponent("project.pbxproj")
        try FileManager.default.copyItem(at: fixture, to: pbxDest)

        let index = try PBXProjParser(projectDir: root.path, srcroot: srcroot.path).parse(targetName: "SampleApp")
        XCTAssertTrue(index.sourcePaths.contains { $0.hasSuffix("AppDelegate.swift") })
        XCTAssertTrue(index.resourcePaths.contains { $0.hasSuffix("hero.png") })
    }
}
