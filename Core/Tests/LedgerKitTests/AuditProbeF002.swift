import Foundation
import Testing
@testable import LedgerKit

// Regression for F-002 (fixed): a corrupt ledger file is quarantined, not
// wiped. The next append writes a fresh file while the original bytes are
// preserved on disk for recovery.
@Suite("F-002 ledger corruption quarantine")
struct AuditProbeF002 {
    @Test("Corrupt ledger + append quarantines the original, never destroys it")
    func corruptionQuarantines() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "f002-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "ledger.json")

        // Years of history, corrupted by a bad byte run.
        let corruptBytes = "{corrupt!!! but this used to be years of history"
        try Data(corruptBytes.utf8).write(to: file)

        let store = LedgerStore(fileURL: file)
        _ = await store.events()   // triggers load + quarantine
        await store.append(LedgerEvent(kind: .snapshot, title: "new", detail: "post-corruption"))

        // The live ledger now holds only the new event (fresh start)…
        let after = await LedgerStore(fileURL: file).events()
        #expect(after.count == 1)

        // …but the original corrupt bytes were preserved, not destroyed.
        let quarantines = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains("corrupt") }
        #expect(!quarantines.isEmpty, "corrupt file must be quarantined")
        let preserved = try String(contentsOf: dir.appending(path: quarantines[0]), encoding: .utf8)
        #expect(preserved == corruptBytes, "quarantined bytes must be intact for recovery")
    }

    @Test("Absent file is a clean first run, no quarantine")
    func absentFileClean() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "f002b-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = LedgerStore(fileURL: dir.appending(path: "ledger.json"))
        await store.append(LedgerEvent(kind: .snapshot, title: "first", detail: "clean"))
        let events = await store.events()
        #expect(events.count == 1)
        let quarantines = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains("corrupt") }
        #expect(quarantines.isEmpty)
    }
}
