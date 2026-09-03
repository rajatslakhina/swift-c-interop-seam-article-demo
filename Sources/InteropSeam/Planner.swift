/// The result of planning one seam under one layout.
public struct SeamPlan: Sendable {
    public let layout: SeamLayout
    /// Placement for every declared C name.
    public let placements: [String: Placement]
    public let diagnostics: [SeamDiagnostic]

    public init(layout: SeamLayout, placements: [String: Placement], diagnostics: [SeamDiagnostic]) {
        self.layout = layout
        self.placements = placements
        self.diagnostics = diagnostics
    }

    public func placement(of name: String) -> Placement? {
        placements[name]
    }

    public func count(_ placement: Placement) -> Int {
        placements.values.filter { $0 == placement }.count
    }

    /// Declarations a dependent package can see after `import`.
    public var downstreamVisibleCount: Int {
        switch layout {
        case .shimTarget:
            // Everything in the umbrella is public. There is no other setting.
            return placements.count
        case .designedSeam:
            return count(.publicHeaders)
        }
    }

    public var totalCount: Int { placements.count }

    /// Fraction of the C surface a dependent can see. 1.0 means "all of it".
    public var exposureRatio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(downstreamVisibleCount) / Double(totalCount)
    }

    public func diagnostics(with code: SeamDiagnostic.Code) -> [SeamDiagnostic] {
        diagnostics.filter { $0.code == code }
    }
}

/// Decides, for every C declaration, which side of the SE-0541 seam it has to
/// sit on. The rules are the proposal's rules, not opinions:
///
/// 1. A library target's bridging header is `.internal` only. So any C name
///    that appears in a `public` Swift signature cannot come from the bridging
///    header; it must be in `include/`.
/// 2. If a declaration is in `include/`, everything its own signature depends
///    on must be importable there too, transitively.
/// 3. Everything else Swift touches can hide behind the bridging header.
/// 4. Everything Swift never touches is unreferenced. The old umbrella
///    exported it anyway.
public struct SeamPlanner: Sendable {
    public init() {}

    public func plan(_ model: SeamModel, layout: SeamLayout) -> SeamPlan {
        var diagnostics: [SeamDiagnostic] = []
        let byName = model.declarationsByName

        // Duplicate declarations: the dictionary kept the last one, say so.
        var seenNames: Set<String> = []
        for d in model.declarations {
            if !seenNames.insert(d.name).inserted {
                diagnostics.append(SeamDiagnostic(
                    code: .duplicateDeclaration, severity: .warning, subject: d.name,
                    message: "\(d.name) is declared more than once; the last declaration (\(d.header)) was used."))
            }
        }

        // Direct usage classification.
        var publicRoots: Set<String> = []
        var internalUses: Set<String> = []
        for use in model.uses {
            guard byName[use.declaration] != nil else {
                diagnostics.append(SeamDiagnostic(
                    code: .danglingUse, severity: .error, subject: use.declaration,
                    message: "\(use.swiftAPI) uses \(use.declaration), which no header in the model declares."))
                continue
            }
            switch use.site {
            case .publicSignature:
                publicRoots.insert(use.declaration)
                diagnostics.append(SeamDiagnostic(
                    code: .publicAPILeak, severity: .warning, subject: use.declaration,
                    message: "\(use.swiftAPI) exposes \(use.declaration) in a public signature. Under SE-0541 that pins \(use.declaration) to include/ for every dependent, forever. Wrap it or accept the contract."))
            case .internalBody:
                internalUses.insert(use.declaration)
            }
        }

        // Transitive closure over dependsOn from the public roots.
        var publicSet = publicRoots
        var frontier = Array(publicRoots)
        while let current = frontier.popLast() {
            guard let decl = byName[current] else { continue }
            for dep in decl.dependsOn where byName[dep] != nil && !publicSet.contains(dep) {
                publicSet.insert(dep)
                frontier.append(dep)
                diagnostics.append(SeamDiagnostic(
                    code: .transitivePromotion, severity: .note, subject: dep,
                    message: "\(dep) is public only because \(current) depends on it."))
            }
        }

        // Transitive closure over dependsOn from internal uses (still internal).
        var internalSet = internalUses.subtracting(publicSet)
        frontier = Array(internalSet)
        while let current = frontier.popLast() {
            guard let decl = byName[current] else { continue }
            for dep in decl.dependsOn where byName[dep] != nil && !publicSet.contains(dep) && !internalSet.contains(dep) {
                internalSet.insert(dep)
                frontier.append(dep)
            }
        }

        var placements: [String: Placement] = [:]
        for d in model.declarations {
            if publicSet.contains(d.name) {
                placements[d.name] = .publicHeaders
            } else if internalSet.contains(d.name) {
                placements[d.name] = .bridgingHeader
            } else {
                placements[d.name] = .unreferenced
            }
        }

        // Straddling headers only matter under the designed seam: the umbrella
        // layout has exactly one place for everything.
        if layout == .designedSeam {
            for header in model.headers {
                let inHeader = model.declarations.filter { $0.header == header }
                let hasPublic = inHeader.contains { placements[$0.name] == .publicHeaders }
                let hasBridged = inHeader.contains { placements[$0.name] == .bridgingHeader }
                if hasPublic && hasBridged {
                    let publicNames = inHeader.filter { placements[$0.name] == .publicHeaders }.map(\.name)
                    diagnostics.append(SeamDiagnostic(
                        code: .straddlingHeader, severity: .error, subject: header,
                        message: "\(header) holds both include/ declarations (\(publicNames.joined(separator: ", "))) and bridging-header declarations. A bridging header cannot live inside the public headers directory, so this file has to split."))
                }
            }
        }

        return SeamPlan(layout: layout, placements: placements, diagnostics: diagnostics)
    }

    /// Plan the same model both ways so the difference is a number, not a feeling.
    public func compare(_ model: SeamModel) -> (legacy: SeamPlan, designed: SeamPlan) {
        (plan(model, layout: .shimTarget), plan(model, layout: .designedSeam))
    }
}
