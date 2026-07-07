import Foundation
import Testing
@testable import ScannerKit

// AUDIT PROBE F-003: SizeCache keys are raw path strings. The same
// directory reached via a symlink alias gets a second, independent entry —
// and invalidating one alias leaves the other stale.
@Suite("Audit probe F-003")
struct AuditProbeF003 {
    @Test("Symlink alias defeats cache invalidation")
    func aliasStaleness() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "audit-f003-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let real = root.appending(path: "real")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appending(path: "alias")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let cache = SizeCache(fileURL: root.appending(path: "cache.json"))
        await cache.store(path: real.path, mtime: 42, size: 1000)

        // Same directory via alias: cache miss (two-key world confirmed)…
        #expect(await cache.lookup(path: link.path, mtime: 42) == nil)

        // …and invalidating via the alias does NOT clear the real entry.
        await cache.invalidate(subtree: link.path)
        #expect(await cache.lookup(path: real.path, mtime: 42)?.size == 1000,
                "stale entry survives invalidation through the alias")
    }
}
