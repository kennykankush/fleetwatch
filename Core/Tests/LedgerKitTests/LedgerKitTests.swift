import Foundation
import Testing
@testable import LedgerKit

@Suite("Ledger store")
struct LedgerStoreTests {
    @Test("Append and read round-trips through disk")
    func roundTrip() async throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "stockpile-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = LedgerStore(fileURL: file)
        await store.append(LedgerEvent(kind: .snapshot, title: "Snapshot", detail: "test", bytes: 42))
        await store.append(LedgerEvent(kind: .startup, title: "Disabled agent", detail: "com.example.thing"))

        // A fresh store instance must read the same events back from disk.
        let reread = LedgerStore(fileURL: file)
        let events = await reread.events()
        #expect(events.count == 2)
        #expect(events[0].kind == .snapshot)
        #expect(events[0].bytes == 42)
        #expect(events[1].kind == .startup)

        let latest = await reread.latestSnapshot()
        #expect(latest?.title == "Snapshot")
    }
}
