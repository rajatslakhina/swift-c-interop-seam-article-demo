# InteropSeam — plan the Swift/C seam SE-0541 finally lets you design

**Article:** [Your Objective-C Umbrella Exports 16 Declarations. Under SE-0541, One Has to Stay Public — and It's a Leak.](https://medium.com/@er.rajatlakhina/your-objective-c-umbrella-exports-16-declarations-ddb8c69ab268) (Medium)

SE-0541 *Flexible Swift/C Interoperability for Packages* was accepted by the Ecosystem Steering Group; the acceptance was announced on 25 August 2026. It lets one
package target mix Swift and C-family sources, and it lets a Swift target reach non-modular C through a
bridging header — with one rule that matters more than the feature: **a library target's bridging header
can only be `.internal`.** Anything a `public` Swift signature mentions cannot come from the bridging
header. It has to sit in `include/`, where every dependent can see it, forever.

That rule turns "where does this header go?" into an architecture decision with a right answer per
declaration. `InteropSeam` computes that answer for a modelled codebase and shows what the old
shim-target-plus-umbrella workaround was exposing all along.

## What the demo shows

The fixture (`LegacyLedgerFixture`) is an ordinary legacy Objective-C ledger core: **16 declarations
across 5 headers**, currently exported through one umbrella because that was the only shape SwiftPM
could express. The Swift wrapper uses nine of them; one public initializer leaks the raw `LCLedger`
handle into its signature.

`SeamPlanner` plans it both ways:

| Layout | Downstream-visible C declarations |
|---|---|
| Shim target + umbrella (pre-SE-0541) | **16 / 16** — the umbrella has one visibility, and it is public |
| Mixed target + `.internal` bridging header (SE-0541) | **1 / 16** — `LCLedger`, and only because the public initializer leaks it |

Under the designed seam the remaining fifteen split into **10** that belong behind the bridging header
(the eight Swift bodies call directly, plus `LCEntry` and `LCKeyRef`, which they depend on) and **5** the
Swift side never touches at all. The planner also raises the two things a build system will never tell you:

- `publicAPILeak` — `Ledger.init(handle:)` pins `LCLedger` to `include/` for every dependent.
- `straddlingHeader` — `LCLedger.h` now holds one `include/` declaration and three bridging-header
  declarations, and SE-0541 forbids the bridging header from living inside the public headers
  directory, so the file has to split.

## The rules, as code

```swift
// 1. A library's bridging header is .internal only, so anything in a
//    public Swift signature must be in include/.
case .publicSignature:
    publicRoots.insert(use.declaration)

// 2. Whatever a public declaration's own signature depends on is public too.
while let current = frontier.popLast() {
    for dep in decl.dependsOn where !publicSet.contains(dep) {
        publicSet.insert(dep)
        frontier.append(dep)
    }
}

// 3. Everything else Swift touches hides behind the bridging header.
// 4. Everything Swift never touches is unreferenced — the umbrella exported it anyway.
```

```swift
let planner = SeamPlanner()
let (legacy, designed) = planner.compare(LegacyLedgerFixture.model)
legacy.downstreamVisibleCount    // 16
designed.downstreamVisibleCount  // 1
designed.count(.bridgingHeader)  // 10
designed.count(.unreferenced)    // 5
designed.diagnostics(with: .straddlingHeader).first?.subject  // "LCLedger.h"
```

## Layout

```
Package.swift                       library product `InteropSeam` + test target (no executableTarget)
Sources/InteropSeam/
  Model.swift                       CDeclaration, SwiftUse, SeamModel
  Layout.swift                      SeamLayout (.shimTarget / .designedSeam), Placement
  Diagnostics.swift                 SeamDiagnostic + codes
  Planner.swift                     SeamPlanner, SeamPlan
  LegacyLedgerFixture.swift         the 16-declaration legacy core
  SeamDemoView.swift                SwiftUI screen: both layouts, placements, diagnostics
Tests/InteropSeamTests/             16 tests: fixture numbers, transitive promotion, dangling
                                    use, duplicates, cycles, empty model
Demo.xcodeproj                      iOS app consuming the package via XCLocalSwiftPackageReference
Demo/DemoApp.swift                  @main App showing SeamDemoView
```

The planner does not parse headers. You feed it a model — by hand, or from a script over your own
`include/` directory — because the point is the placement rules, and they can be reasoned about and
tested before a toolchain that ships SE-0541 exists.

## How to run it

```
git clone https://github.com/rajatslakhina/swift-c-interop-seam-article-demo.git
cd swift-c-interop-seam-article-demo
open Demo.xcodeproj      # pick the Demo scheme and any iPhone Simulator, then Build & Run
swift test               # library + 16 tests, no Xcode needed
```

No other setup. `Demo.xcodeproj` references the package at `.` so a single clone is enough.

## Verification status

- `swift build` — passes (Swift 6.0.3, Linux aarch64, Swift 6 language mode).
- `swift test` — **16 / 16 pass**.
- `Demo.xcodeproj/project.pbxproj` — hand-authored; braces and parentheses balance, and every object
  id referenced is defined.
- **Simulator run: not completed in the cycle that produced this repo.** The session that built it
  runs unattended and macOS screen-control access cannot be approved during a scheduled run, so Xcode
  was never opened and there are no app screenshots. `Demo/Screenshots/` is deliberately empty rather
  than carrying a placeholder or a diagram relabelled as a capture. The SwiftUI layer was reviewed
  by hand against iOS 17 APIs (`NavigationStack`, segmented `Picker`, `GeometryReader` bar,
  `Capsule` chips). If you run it and something is off, open an issue.

## Source

- [SE-0541: Flexible Swift/C Interoperability for Packages](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0541-flexible-swift-c-interoperability-for-packages.md)
- [Acceptance announcement — Swift Forums, 25 Aug 2026](https://forums.swift.org/t/accepted-se-0541-flexible-swift-c-interoperability-for-packages/89183)
- [SE-0403: Package Manager Mixed Language Target Support](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0403-swiftpm-mixed-language-targets.md) (the earlier attempt)

MIT licensed.
