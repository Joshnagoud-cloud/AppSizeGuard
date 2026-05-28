import Foundation

public enum DiagnosticSeverity: String {
    case warning
    case error
    case note
}

public enum DiagnosticCategory: String {
    case assets = "Assets"
    case duplicates = "Duplicates"
    case unused = "Unused"
    case dependencies = "Dependencies"
    case growth = "Growth"
    case general = "AppSizeGuard"
}

public struct Diagnostic: Equatable {
    public let severity: DiagnosticSeverity
    public let category: DiagnosticCategory
    public let path: String
    public let line: Int
    public let column: Int
    public let message: String

    public init(
        severity: DiagnosticSeverity,
        category: DiagnosticCategory,
        path: String,
        line: Int = 1,
        column: Int = 1,
        message: String
    ) {
        self.severity = severity
        self.category = category
        self.path = (path as NSString).standardizingPath
        self.line = line
        self.column = column
        self.message = message
    }
}
