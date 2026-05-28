import XCTest
@testable import AppSizeGuardLib

final class PBXProjDiscoveryTests: XCTestCase {
    private let minimalPbxproj = """
    // !$*UTF8*$!
    {
    \tobjects = {
    \t\tAA0000000000000000000001 /* hero.png in Resources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000001; };
    \t\tAA0000000000000000000002 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000002; };
    \t\tBB0000000000000000000001 /* hero.png */ = {isa = PBXFileReference; path = hero.png; sourceTree = SOURCE_ROOT; };
    \t\tBB0000000000000000000002 /* AppDelegate.swift */ = {isa = PBXFileReference; path = AppDelegate.swift; sourceTree = SOURCE_ROOT; };
    \t\tDD0000000000000000000001 = { isa = PBXGroup; children = ( BB0000000000000000000001, BB0000000000000000000002 ); sourceTree = "<group>"; };
    \t\tEE0000000000000000000001 /* SampleApp */ = {
    \t\t\tisa = PBXNativeTarget;
    \t\t\tbuildPhases = ( CC0000000000000000000002 /* Sources */, CC0000000000000000000003 /* Resources */, );
    \t\t\tname = SampleApp;
    \t\t\tproductType = "com.apple.product-type.application";
    \t\t};
    \t\tGG0000000000000000000001 /* Project object */ = { isa = PBXProject; mainGroup = DD0000000000000000000001; targets = ( EE0000000000000000000001 ); };
    \t\tCC0000000000000000000003 /* Resources */ = { isa = PBXResourcesBuildPhase; files = ( AA0000000000000000000001 ); };
    \t\tCC0000000000000000000002 /* Sources */ = { isa = PBXSourcesBuildPhase; files = ( AA0000000000000000000002 ); };
    \t};
    \trootObject = GG0000000000000000000001;
    }
    """

    func testPrefersAppXcodeprojOverPods() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appProj = root.appendingPathComponent("MyApp.xcodeproj")
        let podsProj = root.appendingPathComponent("Pods/Pods.xcodeproj")
        try FileManager.default.createDirectory(at: appProj, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: podsProj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = Bundle.module.url(forResource: "minimal", withExtension: "pbxproj", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "minimal.pbxproj", withExtension: nil)
        if let fixture {
            try FileManager.default.copyItem(at: fixture, to: appProj.appendingPathComponent("project.pbxproj"))
        } else {
            try minimalPbxproj.write(to: appProj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        }
        try "// pods".write(to: podsProj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

        let parser = PBXProjParser(projectDir: root.path, srcroot: root.path)
        let index = try parser.parse(targetName: "SampleApp")
        XCTAssertTrue(index.pbxprojPath.contains("MyApp.xcodeproj"))
        XCTAssertFalse(index.pbxprojPath.contains("/Pods/"))
    }

    func testGroupRelativeJSONPathResolves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("Resources/Gif Json")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let json = resources.appendingPathComponent("hotpromo.json")
        try Data(count: 4).write(to: json)

        let pbx = """
        // !$*UTF8*$!
        {
        \tobjects = {
        /* Begin PBXBuildFile section */
        \t\tAA0000000000000000000001 /* hotpromo.json in Resources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000001; };
        /* End PBXBuildFile section */
        /* Begin PBXFileReference section */
        \t\tBB0000000000000000000001 /* hotpromo.json */ = {isa = PBXFileReference; path = hotpromo.json; sourceTree = "<group>"; };
        /* End PBXFileReference section */
        /* Begin PBXGroup section */
        \t\tDD0000000000000000000002 /* Gif Json */ = {
        \t\t\tisa = PBXGroup;
        \t\t\tchildren = ( BB0000000000000000000001 /* hotpromo.json */, );
        \t\t\tpath = "Gif Json";
        \t\t\tsourceTree = "<group>";
        \t\t};
        \t\tDD0000000000000000000001 /* Resources */ = {
        \t\t\tisa = PBXGroup;
        \t\t\tchildren = ( DD0000000000000000000002 /* Gif Json */, );
        \t\t\tpath = Resources;
        \t\t\tsourceTree = "<group>";
        \t\t};
        \t\tDD0000000000000000000003 = {
        \t\t\tisa = PBXGroup;
        \t\t\tchildren = ( DD0000000000000000000001 /* Resources */, );
        \t\t\tsourceTree = "<group>";
        \t\t};
        /* End PBXGroup section */
        /* Begin PBXNativeTarget section */
        \t\tEE0000000000000000000001 /* SampleApp */ = {
        \t\t\tisa = PBXNativeTarget;
        \t\t\tbuildPhases = ( CC0000000000000000000003 /* Resources */, );
        \t\t\tname = SampleApp;
        \t\t\tproductType = "com.apple.product-type.application";
        \t\t};
        /* End PBXNativeTarget section */
        /* Begin PBXProject section */
        \t\tGG0000000000000000000001 /* Project object */ = {
        \t\t\tisa = PBXProject;
        \t\t\tmainGroup = DD0000000000000000000003;
        \t\t\ttargets = ( EE0000000000000000000001 /* SampleApp */, );
        \t\t};
        /* End PBXProject section */
        /* Begin PBXResourcesBuildPhase section */
        \t\tCC0000000000000000000003 /* Resources */ = {
        \t\t\tisa = PBXResourcesBuildPhase;
        \t\t\tfiles = ( AA0000000000000000000001 /* hotpromo.json in Resources */, );
        \t\t};
        /* End PBXResourcesBuildPhase section */
        \t};
        \trootObject = GG0000000000000000000001;
        }
        """
        let xcodeproj = root.appendingPathComponent("Sample.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        try pbx.write(to: xcodeproj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

        let index = try PBXProjParser(projectDir: root.path, srcroot: root.path).parse(targetName: "SampleApp")
        XCTAssertTrue(index.resourcePaths.contains { $0.hasSuffix("Resources/Gif Json/hotpromo.json") })
    }
}
