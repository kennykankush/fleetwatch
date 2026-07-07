import Foundation
import Testing
@testable import ScannerKit

// Regression for F-003 (fixed): SizeCache canonicalizes keys, so the same
// directory reached via a symlink alias shares one entry — a lookup through
// the alias hits, and invalidation through any alias clears it.
@Suite("F-003 cache alias canonicalization")
struct AuditProbeF003 {
    @Test("Alias and real path share one cache entry")
    func aliasSharesEntry() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "f003-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let real = root.appending(path: "real")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appending(path: "alias")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let cache = SizeCache(fileURL: root.appending(path: "cache.json"))
        await cache.store(path: real.path, mtime: 42, size: 1000)

        // Same directory via the alias now HITS (one canonical key).
        #expect(await cache.lookup(path: link.path, mtime: 42)?.size == 1000)
    }

    @Test("Invalidation through an alias clears the real entry")
    func aliasInvalidates() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "f003b-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let real = root.appending(path: "real")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appending(path: "alias")
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let cache = SizeCache(fileURL: root.appending(path: "cache.json"))
        await cache.store(path: real.path, mtime: 42, size: 1000)

        await cache.invalidate(subtree: link.path)
        #expect(await cache.lookup(path: real.path, mtime: 42) == nil,
                "invalidation through the alias must clear the canonical entry")
    }
}
