/// Something the planner wants a human to decide about. None of these are
/// fatal to planning; all of them are things a build system will never tell you.
public struct SeamDiagnostic: Hashable, Sendable {
    public enum Severity: String, Hashable, Sendable {
        case error, warning, note
    }

    public enum Code: String, Hashable, Sendable {
        /// A Swift `public` signature exposes a C type. Under SE-0541 that type
        /// is forced into `include/` and becomes part of your contract forever.
        case publicAPILeak
        /// One header holds declarations bound for `include/` and declarations
        /// bound for the bridging header. SE-0541 forbids the bridging header
        /// from living inside the public headers directory, so the file must split.
        case straddlingHeader
        /// Swift references a C name the model never declared.
        case danglingUse
        /// The same C name is declared twice.
        case duplicateDeclaration
        /// A declaration is public only because something else public depends
        /// on it, not because Swift's API names it directly.
        case transitivePromotion
    }

    public let code: Code
    public let severity: Severity
    /// The declaration or header this is about.
    public let subject: String
    public let message: String

    public init(code: Code, severity: Severity, subject: String, message: String) {
        self.code = code
        self.severity = severity
        self.subject = subject
        self.message = message
    }
}
