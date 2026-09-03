/// A single declaration that lives on the C / Objective-C side of the seam.
///
/// The planner never parses real headers. It works on a model you assemble
/// (by hand, from a script over your own `include/` directory, or from a
/// fixture like `LegacyLedgerFixture`) so the placement rules can be reasoned
/// about and tested without a toolchain that ships SE-0541 yet.
public struct CDeclaration: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case type, function, constant
    }

    /// The C-visible identifier, e.g. `LCLedgerPost`.
    public let name: String
    /// The header that declares it, e.g. `LCLedger.h`.
    public let header: String
    public let kind: Kind
    /// Other C declarations this one mentions in its own signature.
    /// A function that takes an `LCEntry *` depends on the `LCEntry` type.
    public let dependsOn: [String]

    public init(name: String, header: String, kind: Kind, dependsOn: [String] = []) {
        self.name = name
        self.header = header
        self.kind = kind
        self.dependsOn = dependsOn
    }
}

/// Where a Swift source file touches a C declaration.
public struct SwiftUse: Hashable, Sendable {
    public enum Site: Hashable, Sendable {
        /// The C name appears in the signature of a `public` Swift declaration.
        /// Under SE-0541 a library's bridging header is `.internal`-only, so
        /// anything used here is forced into the public headers directory.
        case publicSignature
        /// The C name is only used inside a function body or a non-public declaration.
        case internalBody
    }

    /// The C declaration being used.
    public let declaration: String
    /// The Swift API doing the using, e.g. `Ledger.post(_:)`.
    public let swiftAPI: String
    public let site: Site

    public init(declaration: String, swiftAPI: String, site: Site) {
        self.declaration = declaration
        self.swiftAPI = swiftAPI
        self.site = site
    }
}

/// The complete picture of one Swift/C seam: everything C declares, and
/// everywhere Swift reaches across.
public struct SeamModel: Sendable {
    public var declarations: [CDeclaration]
    public var uses: [SwiftUse]

    public init(declarations: [CDeclaration], uses: [SwiftUse]) {
        self.declarations = declarations
        self.uses = uses
    }

    /// Declarations keyed by name. Later duplicates win, which the planner
    /// reports as a diagnostic rather than silently accepting.
    public var declarationsByName: [String: CDeclaration] {
        var out: [String: CDeclaration] = [:]
        for d in declarations { out[d.name] = d }
        return out
    }

    /// Distinct header file names in declaration order.
    public var headers: [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for d in declarations where !seen.contains(d.header) {
            seen.insert(d.header)
            out.append(d.header)
        }
        return out
    }
}
