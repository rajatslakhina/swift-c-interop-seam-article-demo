/// The two ways a package can physically arrange the same C code.
public enum SeamLayout: String, CaseIterable, Sendable {
    /// The pre-SE-0541 workaround: a separate C target (`FooCShims`) with an
    /// umbrella header. Every declaration in that umbrella is part of a Clang
    /// module any dependent can `import`, whether or not you meant it to be.
    case shimTarget
    /// SE-0541: one mixed-source target. Headers in `include/` form the
    /// underlying Clang module and are downstream-visible; everything else is
    /// reached through a bridging header whose visibility, for a library
    /// target, can only be `.internal`.
    case designedSeam

    public var title: String {
        switch self {
        case .shimTarget: return "Shim target + umbrella (pre-SE-0541)"
        case .designedSeam: return "Mixed target + bridging header (SE-0541)"
        }
    }
}

/// Where the planner says a declaration should live under the designed seam.
public enum Placement: String, Hashable, Sendable, CaseIterable {
    /// Must sit in `include/` because Swift's public API mentions it (or
    /// something the public API mentions depends on it). Downstream-visible.
    case publicHeaders
    /// Reachable only from Swift bodies; belongs behind the `.internal`
    /// bridging header. Invisible to any package that depends on you.
    case bridgingHeader
    /// Nothing on the Swift side touches it, directly or transitively.
    case unreferenced

    public var title: String {
        switch self {
        case .publicHeaders: return "include/ (public)"
        case .bridgingHeader: return "bridging header (.internal)"
        case .unreferenced: return "unreferenced"
        }
    }
}
