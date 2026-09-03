/// A deliberately ordinary legacy Objective-C core: a ledger with entries,
/// signing, logging and a v1→v2 migration path that nobody has called since
/// 2021. Sixteen declarations across five headers, all currently exported
/// through one `LedgerCore.h` umbrella because that was the only shape
/// SwiftPM could express.
///
/// The Swift side wraps it in a `Ledger` type. One public initializer leaks a
/// C handle type into its signature — the kind of thing that ships when the
/// umbrella exports everything anyway and nothing ever pushed back.
public enum LegacyLedgerFixture {
    public static let model = SeamModel(
        declarations: [
            // LCLedger.h
            CDeclaration(name: "LCLedger", header: "LCLedger.h", kind: .type),
            CDeclaration(name: "LCLedgerOpen", header: "LCLedger.h", kind: .function, dependsOn: ["LCLedger"]),
            CDeclaration(name: "LCLedgerClose", header: "LCLedger.h", kind: .function, dependsOn: ["LCLedger"]),
            CDeclaration(name: "LCLedgerPost", header: "LCLedger.h", kind: .function, dependsOn: ["LCLedger", "LCEntry"]),
            // LCEntry.h
            CDeclaration(name: "LCEntry", header: "LCEntry.h", kind: .type),
            CDeclaration(name: "LCEntryMake", header: "LCEntry.h", kind: .function, dependsOn: ["LCEntry"]),
            CDeclaration(name: "LCEntryValidate", header: "LCEntry.h", kind: .function, dependsOn: ["LCEntry"]),
            // LCCrypto.h
            CDeclaration(name: "LCKeyRef", header: "LCCrypto.h", kind: .type),
            CDeclaration(name: "LCHashBytes", header: "LCCrypto.h", kind: .function),
            CDeclaration(name: "LCSignEntry", header: "LCCrypto.h", kind: .function, dependsOn: ["LCEntry", "LCKeyRef"]),
            CDeclaration(name: "LCKeyLoad", header: "LCCrypto.h", kind: .function, dependsOn: ["LCKeyRef"]),
            // LCLogging.h
            CDeclaration(name: "LCLogLevelDefault", header: "LCLogging.h", kind: .constant),
            CDeclaration(name: "LCLogSetLevel", header: "LCLogging.h", kind: .function),
            CDeclaration(name: "LCLogWrite", header: "LCLogging.h", kind: .function),
            // LCLegacyMigration.h
            CDeclaration(name: "LCMigrateV1ToV2", header: "LCLegacyMigration.h", kind: .function, dependsOn: ["LCLedger"]),
            CDeclaration(name: "LCLegacyRecordCount", header: "LCLegacyMigration.h", kind: .function),
        ],
        uses: [
            // The leak: a public initializer that takes the raw C handle.
            SwiftUse(declaration: "LCLedger", swiftAPI: "Ledger.init(handle:)", site: .publicSignature),
            // Everything else stays inside bodies.
            SwiftUse(declaration: "LCLedgerOpen", swiftAPI: "Ledger.init(path:)", site: .internalBody),
            SwiftUse(declaration: "LCLedgerClose", swiftAPI: "Ledger.deinit", site: .internalBody),
            SwiftUse(declaration: "LCLedgerPost", swiftAPI: "Ledger.post(_:)", site: .internalBody),
            SwiftUse(declaration: "LCEntryMake", swiftAPI: "Ledger.post(_:)", site: .internalBody),
            SwiftUse(declaration: "LCEntryValidate", swiftAPI: "Ledger.post(_:)", site: .internalBody),
            SwiftUse(declaration: "LCHashBytes", swiftAPI: "Entry.digest", site: .internalBody),
            SwiftUse(declaration: "LCSignEntry", swiftAPI: "Ledger.post(_:)", site: .internalBody),
            SwiftUse(declaration: "LCLogWrite", swiftAPI: "Ledger.post(_:)", site: .internalBody),
        ]
    )
}
