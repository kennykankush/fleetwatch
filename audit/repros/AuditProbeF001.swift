import Foundation
import Testing
@testable import InventoryKit

// AUDIT PROBE F-001: LeftoverLocator matches by NAME with no ownership
// check. If a shared directory happens to carry the app's name, uninstall
// sweeps someone else's data into the Trash.
@Suite("Audit probe F-001")
struct AuditProbeF001 {
    @Test("Leftover sweep collects a shared dir that merely shares the name")
    func overCollection() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "audit-f001-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }

        // ~/Library/Application Support/Electron — used by MANY electron dev
        // apps, not just the one being uninstalled.
        let shared = home.appending(path: "Library/Application Support/Electron")
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)
        try Data("someone else's data".utf8).write(to: shared.appending(path: "other-owner.json"))

        let found = LeftoverLocator.find(bundleIdentifier: "fyi.unrelated.devapp", appName: "Electron", home: home)

        // The probe EXPECTS the flaw: passing means over-collection confirmed.
        #expect(found.contains { $0.path == shared.path },
                "over-collection confirmed: name-match swept a shared directory")
    }
}
