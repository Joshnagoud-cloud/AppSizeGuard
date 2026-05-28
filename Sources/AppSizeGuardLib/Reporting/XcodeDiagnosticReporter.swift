import Foundation

public final class XcodeDiagnosticReporter {
    private var diagnostics: [Diagnostic] = []

    public init() {}

    public func emit(_ diagnostic: Diagnostic) {
        diagnostics.append(diagnostic)
        let line = "\(diagnostic.path):\(diagnostic.line):\(diagnostic.column): \(diagnostic.severity.rawValue): [AppSizeGuard/\(diagnostic.category.rawValue)] \(diagnostic.message)"
        print(line)
    }

    public func emitAll(_ items: [Diagnostic]) {
        items.forEach { emit($0) }
    }

    public var collected: [Diagnostic] { diagnostics }
}
