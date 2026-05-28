import Foundation

public struct ResourceReferenceExtractor {
    public private(set) var staticReferences: Set<String> = []
    public private(set) var quotedStringLiterals: Set<String> = []
    /// True when Swift sources use non-literal image names (e.g. `UIImage(named: variable)`).
    public private(set) var hasDynamicImageNameUsage = false

    public init() {}

    public mutating func ingest(paths: [String]) {
        for path in paths {
            let ext = (path as NSString).pathExtension.lowercased()
            switch ext {
            case "swift", "m", "mm":
                ingestSource(at: path)
            case "storyboard", "xib":
                ingestInterfaceBuilder(at: path)
            case "xcassets":
                ingestAssetCatalog(at: path)
            default:
                if path.contains(".xcassets/") {
                    ingestAssetCatalogEntry(at: path)
                }
                break
            }
        }
    }

    private mutating func ingestSource(at path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let patterns: [(String, Int)] = [
            (#"UIImage\s*\(\s*named:\s*"([^"]+)""#, 1),
            (#"UIImage\s*\(\s*named:\s*"([^"]+)"\s*,\s*in:"#, 1),
            (#"UIImage\.gif\s*\(\s*name:\s*"([^"]+)""#, 1),
            (#"\.gif\s*\(\s*name:\s*"([^"]+)""#, 1),
            (#"LottieAnimation\.named\s*\(\s*"([^"]+)""#, 1),
            (#"Animation\.named\s*\(\s*"([^"]+)""#, 1),
            (#"Image\s*\(\s*"([^"]+)""#, 1),
            (#"Color\s*\(\s*"([^"]+)""#, 1),
            (#"NSImage\s*\(\s*named:\s*"?([^")]+)"?"#, 1),
            (#"forResource:\s*"([^"]+)""#, 1),
            (#"url\s*\(\s*forResource:\s*"([^"]+)""#, 1),
            (#"path\s*\(\s*forResource:\s*"([^"]+)""#, 1),
            (#"Bundle\.module\.url\s*\(\s*forResource:\s*"([^"]+)""#, 1),
            (#"Bundle\.module\.path\s*\(\s*forResource:\s*"([^"]+)""#, 1),
            (#"Bundle\.main\.url\s*\(\s*forResource:\s*"([^"]+)""#, 1),
            (#"Bundle\.main\.path\s*\(\s*forResource:\s*"([^"]+)""#, 1),
            (#"#imageLiteral\s*\([^)]*image:\s*"([^"]+)""#, 1),
            (#"\.imageNamed\s*\(\s*"([^"]+)""#, 1),
            (#"named:\s*"([^"]+)""#, 1),
            (#"URL\s*\(\s*fileNamed:\s*"([^"]+)""#, 1),
            (#"fileNamed:\s*"([^"]+)""#, 1),
        ]
        for (pattern, group) in patterns {
            applyRegex(pattern, group: group, in: content)
        }
        registerBundleResourceWithExtension(in: content)
        registerLottieAndBundleAliases(in: content)
        registerJSONNameParameters(in: content)
        indexQuotedStringLiterals(in: content)
        detectDynamicImageNameUsage(in: content)
    }

    private mutating func registerJSONNameParameters(in content: String) {
        let patterns = [
            #"fileName:\s*"([^"]+)""#,
            #"jsonFile(?:Name)?:\s*"([^"]+)""#,
            #"resourceName:\s*"([^"]+)""#,
            #"loadJSON(?:File)?\s*\(\s*"([^"]+)""#,
        ]
        for pattern in patterns {
            registerNames(from: content, pattern: pattern, fileExtensions: ["json"])
        }
    }

    /// Indexes `"..."` literals line-by-line so a `"` in one statement cannot pair with a distant `"` on another line.
    private mutating func indexQuotedStringLiterals(in content: String) {
        guard let regex = try? NSRegularExpression(pattern: #""([^"]+)""#, options: []) else { return }
        for line in content.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            regex.enumerateMatches(in: line, options: [], range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let r = Range(match.range(at: 1), in: line) else { return }
                let literal = String(line[r])
                guard !literal.isEmpty else { return }
                quotedStringLiterals.insert(literal)
                quotedStringLiterals.insert((literal as NSString).deletingPathExtension)
            }
        }
    }

    private mutating func registerBundleResourceWithExtension(in content: String) {
        let pattern = #"(?:path|url)\s*\(\s*forResource:\s*"([^"]+)"\s*,\s*withExtension:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 2,
                  let nameRange = Range(match.range(at: 1), in: content),
                  let extRange = Range(match.range(at: 2), in: content) else { return }
            let name = String(content[nameRange])
            let ext = String(content[extRange])
            guard !name.isEmpty, !ext.isEmpty else { return }
            staticReferences.insert(name)
            staticReferences.insert("\(name).\(ext)")
            quotedStringLiterals.insert(name)
            quotedStringLiterals.insert("\(name).\(ext)")
        }
    }

    public mutating func ingestPropertyLists(paths: [String]) {
        for path in paths {
            let ext = (path as NSString).pathExtension.lowercased()
            guard ext == "plist" else { continue }
            ingestPropertyList(at: path)
        }
    }

    private mutating func ingestPropertyList(at path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return
        }
        collectPropertyListStrings(from: plist)
    }

    private mutating func collectPropertyListStrings(from value: Any) {
        switch value {
        case let string as String:
            guard !string.isEmpty else { return }
            quotedStringLiterals.insert(string)
            quotedStringLiterals.insert((string as NSString).deletingPathExtension)
            staticReferences.insert(string)
            staticReferences.insert((string as NSString).deletingPathExtension)
        case let array as [Any]:
            array.forEach { collectPropertyListStrings(from: $0) }
        case let dict as [String: Any]:
            dict.values.forEach { collectPropertyListStrings(from: $0) }
        default:
            break
        }
    }

    private mutating func ingestInterfaceBuilder(at path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        applyRegex(#"image="([^"]+)""#, group: 1, in: content)
        applyRegex(#"<image name="([^"]+)""#, group: 1, in: content)
        applyRegex(#"catalog="([^"]+)""#, group: 1, in: content)
    }

    private mutating func ingestAssetCatalog(at path: String) {
        let catalogName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".xcassets", with: "")
        if !catalogName.isEmpty {
            staticReferences.insert(catalogName)
        }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return }
        for case let item as String in enumerator {
            if item.hasSuffix(".imageset") {
                let setName = ((item as NSString).lastPathComponent as NSString).deletingPathExtension
                if !setName.isEmpty { staticReferences.insert(setName) }
            }
            if item.hasSuffix(".colorset") {
                let setName = ((item as NSString).lastPathComponent as NSString).deletingPathExtension
                if !setName.isEmpty { staticReferences.insert(setName) }
            }
            if item.hasSuffix("Contents.json") {
                let jsonPath = (path as NSString).appendingPathComponent(item)
                ingestContentsJSON(at: jsonPath, itemPath: item)
            }
        }
    }

    private mutating func ingestAssetCatalogEntry(at path: String) {
        if let setName = imagesetName(from: path) {
            staticReferences.insert(setName)
        }
        if path.hasSuffix("Contents.json") {
            ingestContentsJSON(at: path, itemPath: path)
        }
    }

    private mutating func ingestContentsJSON(at jsonPath: String, itemPath: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let images = json["images"] as? [[String: Any]] {
            for image in images {
                if let filename = image["filename"] as? String {
                    staticReferences.insert((filename as NSString).deletingPathExtension)
                }
            }
        }

        let parent = (itemPath as NSString).deletingLastPathComponent
        let component = (parent as NSString).lastPathComponent
        if component.hasSuffix(".imageset") || component.hasSuffix(".colorset") {
            let setName = (component as NSString).deletingPathExtension
            if !setName.isEmpty { staticReferences.insert(setName) }
        }
    }

    private mutating func registerLottieAndBundleAliases(in content: String) {
        registerNames(
            from: content,
            pattern: #"LottieAnimation\.named\s*\(\s*"([^"]+)""#,
            fileExtensions: ["json"]
        )
        registerNames(
            from: content,
            pattern: #"Animation\.named\s*\(\s*"([^"]+)""#,
            fileExtensions: ["json"]
        )
        registerNames(
            from: content,
            pattern: #"UIImage\.gif\s*\(\s*name:\s*"([^"]+)""#,
            fileExtensions: ["gif"]
        )
        registerNames(
            from: content,
            pattern: #"\.gif\s*\(\s*name:\s*"([^"]+)""#,
            fileExtensions: ["gif"]
        )
    }

    private mutating func registerNames(from content: String, pattern: String, fileExtensions: [String]) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: content) else { return }
            let name = String(content[r])
            guard !name.isEmpty else { return }
            staticReferences.insert(name)
            for ext in fileExtensions {
                staticReferences.insert("\(name).\(ext)")
            }
        }
    }

    private mutating func applyRegex(_ pattern: String, group: Int, in content: String) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > group,
                  let r = Range(match.range(at: group), in: content) else { return }
            let name = String(content[r])
            if !name.isEmpty { staticReferences.insert(name) }
        }
    }

    /// Whether an asset-catalog imageset name is referenced via static Swift / storyboard / XIB patterns.
    public func isImagesetNameReferenced(_ name: String) -> Bool {
        if staticReferences.contains(name) { return true }
        return quotedStringLiterals.contains(name)
    }

    private mutating func detectDynamicImageNameUsage(in content: String) {
        guard !hasDynamicImageNameUsage else { return }
        let patterns = [
            #"UIImage\s*\(\s*named:\s*[A-Za-z_][\w.]*"#,
            #"NSImage\s*\(\s*named:\s*[A-Za-z_][\w.]*"#,
            #"Image\s*\(\s*[A-Za-z_][\w.]*\s*\)"#,
            #"\.imageNamed\s*\(\s*[A-Za-z_][\w.]*"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(content.startIndex..., in: content)
            if regex.firstMatch(in: content, options: [], range: range) != nil {
                hasDynamicImageNameUsage = true
                return
            }
        }
    }

    public func imagesetName(from path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        for part in parts {
            if part.hasSuffix(".imageset") {
                return (part as NSString).deletingPathExtension
            }
            if part.hasSuffix(".colorset") {
                return (part as NSString).deletingPathExtension
            }
        }
        return nil
    }

    public func resourceLabel(for path: String) -> (kind: String, name: String) {
        let fileName = (path as NSString).lastPathComponent
        let ext = (path as NSString).pathExtension.lowercased()

        if path.hasSuffix(".xcassets") {
            let catalog = fileName.replacingOccurrences(of: ".xcassets", with: "")
            return ("Asset catalog", catalog)
        }
        if let setName = imagesetName(from: path) {
            return ("Asset (\(ext.isEmpty ? "imageset" : ext.uppercased()))", setName)
        }
        if ext == "zip" {
            return ("ZIP", fileName)
        }
        if ext == "json" {
            return ("JSON", fileName)
        }
        if ext == "gif" {
            return ("GIF", fileName)
        }
        if ext == "pdf" {
            return ("PDF", fileName)
        }
        if !ext.isEmpty {
            return (ext.uppercased(), fileName)
        }
        return ("Resource", fileName)
    }

    public func resourceBaseName(for path: String) -> String {
        if let setName = imagesetName(from: path) {
            return setName
        }
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "xcassets" {
            return (path as NSString).lastPathComponent.replacingOccurrences(of: ".xcassets", with: "")
        }
        return ContentHasher.normalizedBaseName(for: path)
    }

    public func isReferenced(path: String) -> Bool {
        let base = resourceBaseName(for: path)
        let fileName = (path as NSString).lastPathComponent
        let noExt = (fileName as NSString).deletingPathExtension

        if staticReferences.contains(base) { return true }
        if staticReferences.contains(fileName) { return true }
        if staticReferences.contains(noExt) { return true }

        // Quoted-literal pass: exact name or path-shaped literal only (no substring match on base
        // names — e.g. "Welcome back" must not mark back.png as referenced).
        for literal in quotedStringLiterals {
            if literal == fileName || literal == noExt || literal == base { return true }
            if pathMatchesLiteral(path, literal: literal) { return true }
        }
        return false
    }

    private func pathMatchesLiteral(_ path: String, literal: String) -> Bool {
        guard !literal.isEmpty else { return false }
        // Extension-only literals (e.g. ".json") and very short strings (e.g. "e", "son")
        // must not suffix-match bundle paths — that suppresses almost all unused JSON warnings.
        guard !literal.hasPrefix("."), literal.count >= 4 else { return false }

        let fileName = (path as NSString).lastPathComponent

        if literal.contains("/") {
            if path.hasSuffix(literal) { return true }
            if path.hasSuffix("/\(literal)") { return true }
            if literal.hasSuffix("/\(fileName)") { return true }
        }

        if !literal.hasSuffix(".json") {
            let withJSON = "\(literal).json"
            if path.hasSuffix(withJSON) || path.hasSuffix("/\(withJSON)") { return true }
        }
        if !literal.hasSuffix(".zip") {
            let withZIP = "\(literal).zip"
            if path.hasSuffix(withZIP) || path.hasSuffix("/\(withZIP)") { return true }
        }
        return false
    }

    public mutating func ingestSwiftSourcesForQuotedLiterals(_ paths: [String]) {
        for path in paths {
            let ext = (path as NSString).pathExtension.lowercased()
            guard ["swift", "m", "mm"].contains(ext) else { continue }
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            indexQuotedStringLiterals(in: content)
            registerBundleResourceWithExtension(in: content)
        }
    }
}
