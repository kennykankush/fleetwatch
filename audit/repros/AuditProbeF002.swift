import Foundation
import Testing
@testable import LedgerKit

// AUDIT PROBE F-002: a corrupt ledger file decodes to [], and the next
// append() persists that empty view — silently destroying all history.
@Suite("Audit probe F-002")
struct AuditProbeF002 {
    @Test("Corrupt ledger + one append = entire history replaced silently")
    func corruptionWipes() async throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "audit-f002-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        // A ledger with years of history... corrupted by one bad byte run.
        try Data("{corrupt!!!".utf8).write(to: file)

        let store = LedgerStore(fileURL: file)
        let seen = await store.events()
        #expect(seen.isEmpty, "corruption reads as empty, no error surfaced")

        await store.append(LedgerEvent(kind: .snapshot, title: "new", detail: "post-corruption"))

        // Fresh read: the file now contains ONLY the new event.
        let after = await LedgerStore(fileURL: file).events()
        #expect(after.count == 1, "history silently replaced — wipe confirmed")
    }
}
