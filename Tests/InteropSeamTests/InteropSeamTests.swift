import XCTest
@testable import InteropSeam

final class InteropSeamTests: XCTestCase {
    let planner = SeamPlanner()
    let fixture = LegacyLedgerFixture.model

    // MARK: Fixture-level numbers the article quotes

    func testFixtureHasSixteenDeclarationsAcrossFiveHeaders() {
        XCTAssertEqual(fixture.declarations.count, 16)
        XCTAssertEqual(fixture.headers.count, 5)
    }

    func testShimTargetExposesEverything() {
        let plan = planner.plan(fixture, layout: .shimTarget)
        XCTAssertEqual(plan.downstreamVisibleCount, 16)
        XCTAssertEqual(plan.totalCount, 16)
        XCTAssertEqual(plan.exposureRatio, 1.0, accuracy: 0.0001)
    }

    func testDesignedSeamExposesOnlyTheLeak() {
        let plan = planner.plan(fixture, layout: .designedSeam)
        XCTAssertEqual(plan.downstreamVisibleCount, 1)
        XCTAssertEqual(plan.placement(of: "LCLedger"), .publicHeaders)
        XCTAssertEqual(plan.count(.publicHeaders), 1)
        XCTAssertEqual(plan.count(.bridgingHeader), 10)
        XCTAssertEqual(plan.count(.unreferenced), 5)
    }

    func testDesignedSeamPlacesInternalUsesBehindBridgingHeader() {
        let plan = planner.plan(fixture, layout: .designedSeam)
        for name in ["LCLedgerOpen", "LCLedgerClose", "LCLedgerPost", "LCEntryMake",
                     "LCEntryValidate", "LCHashBytes", "LCSignEntry", "LCLogWrite"] {
            XCTAssertEqual(plan.placement(of: name), .bridgingHeader, name)
        }
    }

    func testInternalTransitiveDependenciesStayInternal() {
        // LCSignEntry is internal and depends on LCEntry + LCKeyRef; both must be
        // reachable from the bridging header but never promoted to include/.
        let plan = planner.plan(fixture, layout: .designedSeam)
        XCTAssertEqual(plan.placement(of: "LCEntry"), .bridgingHeader)
        XCTAssertEqual(plan.placement(of: "LCKeyRef"), .bridgingHeader)
    }

    func testUnreferencedDeclarationsAreNamed() {
        let plan = planner.plan(fixture, layout: .designedSeam)
        for name in ["LCKeyLoad", "LCLogLevelDefault", "LCLogSetLevel", "LCMigrateV1ToV2", "LCLegacyRecordCount"] {
            XCTAssertEqual(plan.placement(of: name), .unreferenced, name)
        }
    }

    func testFixtureDiagnosticsUnderDesignedSeam() {
        let plan = planner.plan(fixture, layout: .designedSeam)
        let leaks = plan.diagnostics(with: .publicAPILeak)
        XCTAssertEqual(leaks.count, 1)
        XCTAssertEqual(leaks.first?.subject, "LCLedger")

        let straddles = plan.diagnostics(with: .straddlingHeader)
        XCTAssertEqual(straddles.count, 1)
        XCTAssertEqual(straddles.first?.subject, "LCLedger.h")
        XCTAssertEqual(straddles.first?.severity, .error)

        XCTAssertTrue(plan.diagnostics(with: .danglingUse).isEmpty)
        XCTAssertTrue(plan.diagnostics(with: .duplicateDeclaration).isEmpty)
    }

    func testShimTargetNeverReportsStraddling() {
        let plan = planner.plan(fixture, layout: .shimTarget)
        XCTAssertTrue(plan.diagnostics(with: .straddlingHeader).isEmpty)
        // The leak is still a leak regardless of layout.
        XCTAssertEqual(plan.diagnostics(with: .publicAPILeak).count, 1)
    }

    // MARK: Rules in isolation

    func testPublicSignatureUsePromotesTransitiveDependencies() {
        let model = SeamModel(
            declarations: [
                CDeclaration(name: "A", header: "a.h", kind: .function, dependsOn: ["B"]),
                CDeclaration(name: "B", header: "b.h", kind: .type, dependsOn: ["C"]),
                CDeclaration(name: "C", header: "c.h", kind: .type),
                CDeclaration(name: "D", header: "d.h", kind: .type),
            ],
            uses: [SwiftUse(declaration: "A", swiftAPI: "Foo.bar(_:)", site: .publicSignature)]
        )
        let plan = planner.plan(model, layout: .designedSeam)
        XCTAssertEqual(plan.placement(of: "A"), .publicHeaders)
        XCTAssertEqual(plan.placement(of: "B"), .publicHeaders)
        XCTAssertEqual(plan.placement(of: "C"), .publicHeaders)
        XCTAssertEqual(plan.placement(of: "D"), .unreferenced)
        let promoted = plan.diagnostics(with: .transitivePromotion).map(\.subject).sorted()
        XCTAssertEqual(promoted, ["B", "C"])
    }

    func testPublicWinsOverInternalForTheSameDeclaration() {
        let model = SeamModel(
            declarations: [CDeclaration(name: "X", header: "x.h", kind: .type)],
            uses: [
                SwiftUse(declaration: "X", swiftAPI: "Foo.internalThing", site: .internalBody),
                SwiftUse(declaration: "X", swiftAPI: "Foo.publicThing", site: .publicSignature),
            ]
        )
        let plan = planner.plan(model, layout: .designedSeam)
        XCTAssertEqual(plan.placement(of: "X"), .publicHeaders)
    }

    func testDanglingUseIsAnErrorAndDoesNotCrash() {
        let model = SeamModel(
            declarations: [CDeclaration(name: "Real", header: "r.h", kind: .function)],
            uses: [SwiftUse(declaration: "Ghost", swiftAPI: "Foo.bar()", site: .internalBody)]
        )
        let plan = planner.plan(model, layout: .designedSeam)
        let dangling = plan.diagnostics(with: .danglingUse)
        XCTAssertEqual(dangling.count, 1)
        XCTAssertEqual(dangling.first?.severity, .error)
        XCTAssertNil(plan.placement(of: "Ghost"))
        XCTAssertEqual(plan.placement(of: "Real"), .unreferenced)
    }

    func testDependencyOnUndeclaredNameIsIgnoredNotCrashed() {
        let model = SeamModel(
            declarations: [CDeclaration(name: "A", header: "a.h", kind: .function, dependsOn: ["Missing"])],
            uses: [SwiftUse(declaration: "A", swiftAPI: "Foo.bar(_:)", site: .publicSignature)]
        )
        let plan = planner.plan(model, layout: .designedSeam)
        XCTAssertEqual(plan.placement(of: "A"), .publicHeaders)
        XCTAssertEqual(plan.totalCount, 1)
    }

    func testDuplicateDeclarationIsReported() {
        let model = SeamModel(
            declarations: [
                CDeclaration(name: "Twice", header: "one.h", kind: .type),
                CDeclaration(name: "Twice", header: "two.h", kind: .type),
            ],
            uses: []
        )
        let plan = planner.plan(model, layout: .designedSeam)
        XCTAssertEqual(plan.diagnostics(with: .duplicateDeclaration).count, 1)
        XCTAssertEqual(plan.totalCount, 1)
    }

    func testEmptyModelIsSafe() {
        let plan = planner.plan(SeamModel(declarations: [], uses: []), layout: .designedSeam)
        XCTAssertEqual(plan.totalCount, 0)
        XCTAssertEqual(plan.downstreamVisibleCount, 0)
        XCTAssertEqual(plan.exposureRatio, 0)
        XCTAssertTrue(plan.diagnostics.isEmpty)
    }

    func testCyclicDependenciesTerminate() {
        let model = SeamModel(
            declarations: [
                CDeclaration(name: "P", header: "p.h", kind: .type, dependsOn: ["Q"]),
                CDeclaration(name: "Q", header: "p.h", kind: .type, dependsOn: ["P"]),
            ],
            uses: [SwiftUse(declaration: "P", swiftAPI: "Foo.bar(_:)", site: .publicSignature)]
        )
        let plan = planner.plan(model, layout: .designedSeam)
        XCTAssertEqual(plan.placement(of: "P"), .publicHeaders)
        XCTAssertEqual(plan.placement(of: "Q"), .publicHeaders)
    }

    func testCompareReturnsBothLayouts() {
        let (legacy, designed) = planner.compare(fixture)
        XCTAssertEqual(legacy.layout, .shimTarget)
        XCTAssertEqual(designed.layout, .designedSeam)
        XCTAssertGreaterThan(legacy.downstreamVisibleCount, designed.downstreamVisibleCount)
    }
}
