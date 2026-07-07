import Foundation
import Testing
@testable import InventoryKit

// Regression for F-001 (fixed): the leftover sweep must not treat a
// name-collision shared directory as safe-to-delete. Bundle-ID paths are
// high-confidence; display-name paths are low-confidence and review-only.
@Suite("F-001 leftover ownership safety")
struct AuditProbeF001 {
    @Test("Name-collision shared dir is low-confidence, never high")
    func nameMatchIsLowConfidence() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "f001-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }

        // ~/Library/Application Support/Electron — shared by many dev apps.
        let shared = home.appending(path: "Library/Application Support/Electron")
        try fm.createDirectory(at: shared, withIntermediateDirectories: true)
        try Data("someone else's data".utf8).write(to: shared.appending(path: "other.json"))

        let found = LeftoverLocator.find(bundleIdentifier: "fyi.unrelated.devapp", appName: "Electron", home: home)

        // It may be surfaced for review, but only as LOW confidence — the
        // sweep filters to high-confidence, so it is never auto-trashed.
        let electron = found.first { $0.path == shared.path }
        #expect(electron?.confidence == .low)
        #expect(!found.contains { $0.path == shared.path && $0.confidence == .high })
    }

    @Test("Bundle-ID paths are high-confidence and swept")
    func bundleIDIsHighConfidence() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "f001b-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }

        let idCache = home.appending(path: "Library/Caches/com.acme.myapp")
        try fm.createDirectory(at: idCache, withIntermediateDirectories: true)

        let found = LeftoverLocator.find(bundleIdentifier: "com.acme.myapp", appName: "MyApp", home: home)
        #expect(found.first { $0.path == idCache.path }?.confidence == .high)
    }

    @Test("A malformed bundle id yields no high-confidence wide paths")
    func malformedBundleID() throws {
        let found = LeftoverLocator.find(bundleIdentifier: "noDotsHere", appName: "X",
                                         home: FileManager.default.temporaryDirectory.appending(path: "empty-\(UUID().uuidString)"))
        #expect(!found.contains { $0.confidence == .high })
    }
}
