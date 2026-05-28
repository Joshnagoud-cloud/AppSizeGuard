import Foundation

public struct ProjectIndex: Equatable {
    public let resourcePaths: [String]
    public let sourcePaths: [String]
    public let pbxprojPath: String
}

public struct PBXProjParser {
    public let projectDir: String
    public let srcroot: String

  private static let excludedPbxprojPathFragments = [
        "/Pods/",
        "/Carthage/",
        "/.build/",
        "/SourcePackages/",
        "/DerivedData/",
    ]

    public init(projectDir: String, srcroot: String) {
        self.projectDir = projectDir
        self.srcroot = srcroot
    }

    public func parse(targetName: String) throws -> ProjectIndex {
        guard let pbxPath = findPbxproj() else {
            throw PBXProjError.pbxprojNotFound
        }
        let content = try String(contentsOfFile: pbxPath, encoding: .utf8)
        let fileRefs = parseFileReferences(from: content)
        let buildFiles = parseBuildFiles(from: content)
        let groups = parseGroups(from: content)
        let parentOf = buildParentMap(groups: groups)
        let syncRoots = parseSynchronizedRootGroups(from: content)
        let targetIDs = parseNativeTargetIDs(from: content, targetName: targetName)
        guard !targetIDs.isEmpty else {
            throw PBXProjError.targetNotFound(targetName)
        }

        var resourcePaths: [String] = []
        var sourcePaths: [String] = []
        let resourceExts = Set([
            "png", "jpg", "jpeg", "gif", "pdf", "json", "mp4", "mov", "m4a", "wav", "mp3", "aac",
            "ttf", "otf", "woff", "woff2", "zip", "storyboard", "xib", "xcassets", "strings",
        ])
        let sourceExts = Set(["swift", "m", "mm", "h", "storyboard", "xib"])

        for targetID in targetIDs {
            let phaseFileIDs = parseBuildPhaseFileIDs(from: content, targetID: targetID)
            for fileID in phaseFileIDs {
                let refID = buildFiles[fileID] ?? fileID

                if let syncRoot = syncRoots[refID] {
                    let resolved = resolveSynchronizedRootPath(syncRoot)
                    collectPaths(
                        at: resolved,
                        resourceExts: resourceExts,
                        sourceExts: sourceExts,
                        resourcePaths: &resourcePaths,
                        sourcePaths: &sourcePaths
                    )
                    continue
                }

                guard let ref = fileRefs[refID] else { continue }
                let resolved = resolvePath(ref, fileRefID: refID, groups: groups, parentOf: parentOf)
                collectPaths(
                    at: resolved,
                    resourceExts: resourceExts,
                    sourceExts: sourceExts,
                    resourcePaths: &resourcePaths,
                    sourcePaths: &sourcePaths
                )
            }
        }

        return ProjectIndex(
            resourcePaths: Array(Set(resourcePaths)).sorted(),
            sourcePaths: Array(Set(sourcePaths)).sorted(),
            pbxprojPath: pbxPath
        )
    }

    private func collectPaths(
        at resolved: String,
        resourceExts: Set<String>,
        sourceExts: Set<String>,
        resourcePaths: inout [String],
        sourcePaths: inout [String]
    ) {
        let pathsToCheck = expandIfDirectory(resolved, resourceExts: resourceExts)

        for path in pathsToCheck {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            if resourceExts.contains(ext) || path.hasSuffix(".xcassets") {
                resourcePaths.append(path)
            }
        }

        if FileManager.default.fileExists(atPath: resolved) {
            let ext = (resolved as NSString).pathExtension.lowercased()
            if sourceExts.contains(ext) {
                sourcePaths.append(resolved)
            }
            if resolved.hasSuffix(".xcassets") {
                sourcePaths.append(resolved)
            }
        }

        var isSourceDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: resolved, isDirectory: &isSourceDir),
           isSourceDir.boolValue,
           !resolved.hasSuffix(".xcassets") {
            guard let enumerator = FileManager.default.enumerator(atPath: resolved) else { return }
            for case let item as String in enumerator {
                let full = (resolved as NSString).appendingPathComponent(item)
                let ext = (item as NSString).pathExtension.lowercased()
                if sourceExts.contains(ext) {
                    sourcePaths.append(full)
                }
            }
        }
    }

    private func findPbxproj() -> String? {
        let fm = FileManager.default
        var discovered: [String] = []

        if projectDir.hasSuffix(".xcodeproj") {
            let path = (projectDir as NSString).appendingPathComponent("project.pbxproj")
            if fm.fileExists(atPath: path), !Self.isExcludedPbxprojPath(path) {
                return path
            }
        }

        for root in [projectDir, srcroot] {
            discovered.append(contentsOf: xcodeprojPbxprojFiles(under: root))
        }

        discovered = Array(Set(discovered)).filter { !Self.isExcludedPbxprojPath($0) }
        if let preferred = discovered.min(by: { $0.count < $1.count }) {
            return preferred
        }

        for root in [projectDir, srcroot] where root != projectDir || discovered.isEmpty {
            guard let enumerator = fm.enumerator(atPath: root) else { continue }
            for case let item as String in enumerator where item.hasSuffix("project.pbxproj") {
                let path = (root as NSString).appendingPathComponent(item)
                if !Self.isExcludedPbxprojPath(path) {
                    discovered.append(path)
                }
            }
        }

        discovered = Array(Set(discovered)).filter { !Self.isExcludedPbxprojPath($0) }
        return discovered.min(by: { $0.count < $1.count })
    }

    private func xcodeprojPbxprojFiles(under root: String) -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        return items.compactMap { item -> String? in
            guard item.hasSuffix(".xcodeproj"), !item.hasPrefix("Pods") else { return nil }
            let path = (root as NSString).appendingPathComponent(item).appending("/project.pbxproj")
            return fm.fileExists(atPath: path) ? path : nil
        }
    }

    private static func isExcludedPbxprojPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return excludedPbxprojPathFragments.contains { lower.contains($0.lowercased()) }
    }

    private struct FileRef {
        let path: String
        let sourceTree: String?
    }

    private struct PBXGroup {
        let path: String?
        let sourceTree: String?
        let children: [String]
    }

    private struct SynchronizedRootGroup {
        let path: String
        let sourceTree: String?
    }

    private func parseFileReferences(from content: String) -> [String: FileRef] {
        parseObjectBlocks(from: content, isa: "PBXFileReference") { block, id in
            let path = capture(group: "path", in: block) ?? capture(group: "name", in: block)
            guard let path, !path.isEmpty else { return nil }
            return FileRef(path: path, sourceTree: capture(group: "sourceTree", in: block))
        }
    }

    private func parseGroups(from content: String) -> [String: PBXGroup] {
        parseObjectBlocks(from: content, isa: "PBXGroup") { block, _ in
            var children: [String] = []
            if let inner = captureList(group: "children", in: block) {
                extractIDs(from: inner, into: &children)
            }
            return PBXGroup(
                path: capture(group: "path", in: block),
                sourceTree: capture(group: "sourceTree", in: block),
                children: children
            )
        }
    }

    private func parseSynchronizedRootGroups(from content: String) -> [String: SynchronizedRootGroup] {
        parseObjectBlocks(from: content, isa: "PBXFileSystemSynchronizedRootGroup") { block, _ in
            guard let path = capture(group: "path", in: block), !path.isEmpty else { return nil }
            return SynchronizedRootGroup(path: path, sourceTree: capture(group: "sourceTree", in: block))
        }
    }

    private func parseObjectBlocks<T>(
        from content: String,
        isa: String,
        transform: (String, String) -> T?
    ) -> [String: T] {
        var results: [String: T] = [:]
        let marker = "isa = \(isa);"
        var searchStart = content.startIndex

        while let isaRange = content.range(of: marker, range: searchStart..<content.endIndex) {
            guard let blockStart = content[..<isaRange.lowerBound].lastIndex(of: "{"),
                  let id = extractID(before: blockStart, in: content),
                  let block = extractBlock(startingAtBrace: blockStart, in: content),
                  let value = transform(block, id) else {
                searchStart = isaRange.upperBound
                continue
            }
            results[id] = value
            searchStart = isaRange.upperBound
        }
        return results
    }

    private func buildParentMap(groups: [String: PBXGroup]) -> [String: String] {
        var parentOf: [String: String] = [:]
        for (groupID, group) in groups {
            for child in group.children {
                parentOf[child] = groupID
            }
        }
        return parentOf
    }

    private func capture(group key: String, in block: String) -> String? {
        let pattern = key + #" = ([^;]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              let r = Range(match.range(at: 1), in: block) else { return nil }
        return String(block[r]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private func captureList(group key: String, in block: String) -> String? {
        let pattern = key + #" = \(([\s\S]*?)\);"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
              let r = Range(match.range(at: 1), in: block) else { return nil }
        return String(block[r])
    }

    private func parseNativeTargetIDs(from content: String, targetName: String) -> [String] {
        var ids: [String] = []
        let marker = "/* \(targetName) */ = {"
        var searchStart = content.startIndex

        while let markerRange = content.range(of: marker, range: searchStart..<content.endIndex) {
            let afterBrace = markerRange.upperBound
            let snippetEnd = content.index(afterBrace, offsetBy: 120, limitedBy: content.endIndex) ?? content.endIndex
            if content[afterBrace..<snippetEnd].contains("isa = PBXNativeTarget"),
               let id = extractID(before: markerRange.lowerBound, in: content) {
                ids.append(id)
            }
            searchStart = markerRange.upperBound
        }

        if ids.isEmpty {
            ids = parseNativeTargetIDsByNameField(from: content, targetName: targetName)
        }
        return Array(Set(ids))
    }

    private func parseNativeTargetIDsByNameField(from content: String, targetName: String) -> [String] {
        var ids: [String] = []
        let nameMarker = "name = \(targetName);"
        let isaMarker = "isa = PBXNativeTarget;"
        var searchStart = content.startIndex

        while let nameRange = content.range(of: nameMarker, range: searchStart..<content.endIndex) {
            let windowStart = content.index(nameRange.lowerBound, offsetBy: -400, limitedBy: content.startIndex) ?? content.startIndex
            let window = content[windowStart..<nameRange.upperBound]
            if window.contains(isaMarker), let id = extractID(before: nameRange.lowerBound, in: content) {
                ids.append(id)
            }
            searchStart = nameRange.upperBound
        }
        return ids
    }

    private func extractID(before index: String.Index, in content: String) -> String? {
        var lineStart = index
        while lineStart > content.startIndex {
            let prev = content.index(before: lineStart)
            if content[prev] == "\n" { break }
            lineStart = prev
        }
        let prefix = content[lineStart..<index]
        guard let regex = try? NSRegularExpression(pattern: #"([A-Fa-f0-9]{24})"#),
              let match = regex.firstMatch(in: String(prefix), range: NSRange(prefix.startIndex..., in: prefix)),
              let r = Range(match.range(at: 1), in: prefix) else { return nil }
        return String(prefix[r])
    }

    private func parseBuildPhaseFileIDs(from content: String, targetID: String) -> [String] {
        guard let targetBlock = extractBlock(afterID: targetID, in: content) else { return [] }

        var phaseIDs: [String] = []
        let buildPhasesPattern = #"buildPhases = \(([\s\S]*?)\);"#
        if let bpRegex = try? NSRegularExpression(pattern: buildPhasesPattern, options: []) {
            let r = NSRange(targetBlock.startIndex..., in: targetBlock)
            if let m = bpRegex.firstMatch(in: targetBlock, options: [], range: r),
               let inner = Range(m.range(at: 1), in: targetBlock) {
                extractIDs(from: String(targetBlock[inner]), into: &phaseIDs)
            }
        }

        var fileIDs: [String] = []
        for phaseID in phaseIDs {
            guard let phaseBlock = extractBlock(afterID: phaseID, in: content) else { continue }
            let filesPattern = #"files = \(([\s\S]*?)\);"#
            guard let filesRegex = try? NSRegularExpression(pattern: filesPattern, options: []) else { continue }
            let fr = NSRange(phaseBlock.startIndex..., in: phaseBlock)
            if let m = filesRegex.firstMatch(in: phaseBlock, options: [], range: fr),
               let innerRange = Range(m.range(at: 1), in: phaseBlock) {
                extractIDs(from: String(phaseBlock[innerRange]), into: &fileIDs)
            }
        }
        return fileIDs
    }

    private func firstID(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"([A-Fa-f0-9]{24})"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private func extractIDs(from text: String, into ids: inout [String]) {
        let idPattern = #"([A-Fa-f0-9]{24})"#
        guard let idRegex = try? NSRegularExpression(pattern: idPattern) else { return }
        let ir = NSRange(text.startIndex..., in: text)
        idRegex.enumerateMatches(in: text, options: [], range: ir) { im, _, _ in
            guard let im, let r = Range(im.range(at: 1), in: text) else { return }
            ids.append(String(text[r]))
        }
    }

    private func parseBuildFiles(from content: String) -> [String: String] {
        var buildFiles: [String: String] = [:]
        let marker = "isa = PBXBuildFile;"
        var searchStart = content.startIndex

        while let isaRange = content.range(of: marker, range: searchStart..<content.endIndex) {
            guard let blockStart = content[..<isaRange.lowerBound].lastIndex(of: "{"),
                  let id = extractID(before: blockStart, in: content),
                  let block = extractBlock(startingAtBrace: blockStart, in: content) else {
                searchStart = isaRange.upperBound
                continue
            }
            if let fileRefLine = capture(group: "fileRef", in: block),
               let fileRefID = firstID(in: fileRefLine) {
                buildFiles[id] = fileRefID
            }
            searchStart = isaRange.upperBound
        }
        return buildFiles
    }

    private func extractBlock(afterID id: String, in content: String) -> String? {
        let pattern = NSRegularExpression.escapedPattern(for: id) + #" /\* [^*]+ \*/ = \{"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        for match in matches {
            guard let matchRange = Range(match.range, in: content) else { continue }
            let braceStart = content.index(before: matchRange.upperBound)
            return extractBlock(startingAtBrace: braceStart, in: content)
        }
        return nil
    }

    private func extractBlock(startingAtBrace braceStart: String.Index, in content: String) -> String? {
        var depth = 0
        var i = braceStart
        while i < content.endIndex {
            switch content[i] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(content[braceStart...i])
                }
            default: break
            }
            i = content.index(after: i)
        }
        return nil
    }

    private func resolvePath(
        _ ref: FileRef,
        fileRefID: String,
        groups: [String: PBXGroup],
        parentOf: [String: String]
    ) -> String {
        let path = ref.path
        if path.hasPrefix("/") { return path }

        switch ref.sourceTree {
        case "SOURCE_ROOT":
            return firstExistingPath(
                under: [srcroot, srcrootForProject()],
                relative: path
            ) ?? (srcroot as NSString).appendingPathComponent(path)
        case "SDKROOT", "DEVELOPER_DIR", "BUILT_PRODUCTS_DIR":
            return path
        default:
            let relative = groupRelativePath(for: fileRefID, fileName: path, groups: groups, parentOf: parentOf)
            if let existing = firstExistingPath(under: [srcroot, srcrootForProject(), projectDir], relative: relative) {
                return existing
            }
            let fileName = (path as NSString).lastPathComponent
            if let found = findFile(named: fileName, under: srcroot)
                ?? findFile(named: fileName, under: srcrootForProject())
                ?? findFile(named: fileName, under: projectDir) {
                return found
            }
            return (srcroot as NSString).appendingPathComponent(relative)
        }
    }

    private func resolveSynchronizedRootPath(_ group: SynchronizedRootGroup) -> String {
        if group.path.hasPrefix("/") { return group.path }
        switch group.sourceTree {
        case "SOURCE_ROOT":
            return firstExistingPath(under: [srcroot, srcrootForProject()], relative: group.path)
                ?? (srcroot as NSString).appendingPathComponent(group.path)
        default:
            return firstExistingPath(under: [projectDir, srcroot, srcrootForProject()], relative: group.path)
                ?? (srcroot as NSString).appendingPathComponent(group.path)
        }
    }

    private func srcrootForProject() -> String {
        if projectDir.hasSuffix(".xcodeproj") {
            return (projectDir as NSString).deletingLastPathComponent
        }
        return projectDir
    }

    private func groupRelativePath(
        for fileRefID: String,
        fileName: String,
        groups: [String: PBXGroup],
        parentOf: [String: String]
    ) -> String {
        var parts = [fileName]
        var current = parentOf[fileRefID]
        while let groupID = current, let group = groups[groupID] {
            if let groupPath = group.path, !groupPath.isEmpty {
                parts.insert(groupPath, at: 0)
            }
            current = parentOf[groupID]
        }
        return parts.joined(separator: "/")
    }

    private func firstExistingPath(under roots: [String], relative: String) -> String? {
        for root in roots {
            let candidate = (root as NSString).appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func expandIfDirectory(_ path: String, resourceExts: Set<String>) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return [path]
        }

        if path.hasSuffix(".xcassets") {
            return enumerateAssetCatalog(at: path, resourceExts: resourceExts)
        }

        var results: [String] = []
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return [path] }
        for case let item as String in enumerator {
            let full = (path as NSString).appendingPathComponent(item)
            let ext = (item as NSString).pathExtension.lowercased()
            if resourceExts.contains(ext) || item.hasSuffix(".xcassets") {
                results.append(full)
            }
        }
        return results.isEmpty ? [path] : results
    }

    private func enumerateAssetCatalog(at path: String, resourceExts: Set<String>) -> [String] {
        var results = [path]
        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return results }
        for case let item as String in enumerator {
            let ext = (item as NSString).pathExtension.lowercased()
            guard resourceExts.contains(ext) else { continue }
            results.append((path as NSString).appendingPathComponent(item))
        }
        return results
    }

    private func findFile(named fileName: String, under directory: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return nil }
        for case let item as String in enumerator {
            if (item as NSString).lastPathComponent == fileName {
                return (directory as NSString).appendingPathComponent(item)
            }
        }
        return nil
    }
}

public enum PBXProjError: LocalizedError {
    case pbxprojNotFound
    case targetNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .pbxprojNotFound:
            return "Could not find project.pbxproj"
        case .targetNotFound(let name):
            return "Target '\(name)' not found in project.pbxproj"
        }
    }
}
