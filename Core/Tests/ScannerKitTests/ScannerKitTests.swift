import Foundation
import Testing
@testable import ScannerKit
import RulesKit

@Suite("Disk accounting")
struct DiskAccountingTests {
    @Test("Boot volume yields sane numbers")
    func bootVolume() throws {
        let accounting = try DiskAccounting.measure()
        #expect(accounting.totalCapacity > 0)
        #expect(accounting.physicalFree > 0)
        #expect(accounting.physicalFree <= accounting.totalCapacity)
        // Effective free counts purgeable, so it can never be less than strict free.
        #expect(accounting.effectiveFree >= accounting.physicalFree)
        #expect((0.0...1.0).contains(accounting.physicalUsedFraction))
        #expect((0.0...1.0).contains(accounting.effectiveUsedFraction))
        #expect(accounting.purgeable == accounting.effectiveFree - accounting.physicalFree)
    }
}

@Suite("Directory scanner")
struct DirectoryScannerTests {
    @Test("Sizes children and annotates recognized directories")
    func scanFixture() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "stockpile-scan-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        // project/node_modules (recognized, 🟡) beside package.json,
        // plus documents/ (user data) holding a 1MB file.
        let project = root.appending(path: "project")
        let nodeModules = project.appending(path: "node_modules/dep")
        try fm.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appending(path: "package.json"))
        try Data(repeating: 0xAB, count: 256 * 1024).write(to: nodeModules.appending(path: "blob.bin"))

        let documents = root.appending(path: "documents")
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 1024 * 1024).write(to: documents.appending(path: "thesis.pdf"))

        let scanner = DirectoryScanner(registry: try RulesRegistry.bundled())

        let rootEntries = try await scanner.children(of: root)
        #expect(rootEntries.count == 2)
        // Sorted largest first: documents (1MB) before project (256KB).
        #expect(rootEntries.first?.name == "documents")
        #expect(rootEntries.allSatisfy { $0.sizeBytes > 0 })
        // Neither top-level dir is itself recognized.
        #expect(rootEntries.allSatisfy { $0.rule == nil })

        let projectEntries = try await scanner.children(of: project)
        let nm = try #require(projectEntries.first { $0.name == "node_modules" })
        #expect(nm.rule?.id == "node-modules")
        #expect(nm.rule?.tier == .regenerable)
        #expect(nm.sizeBytes >= 256 * 1024)
    }

    @Test("Symlinks are counted as zero, never followed")
    func symlinksNotFollowed() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "stockpile-link-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let big = root.appending(path: "big")
        try fm.createDirectory(at: big, withIntermediateDirectories: true)
        try Data(repeating: 0xEF, count: 512 * 1024).write(to: big.appending(path: "payload.bin"))
        try fm.createSymbolicLink(
            at: root.appending(path: "link-to-big"),
            withDestinationURL: big
        )

        let scanner = DirectoryScanner(registry: try RulesRegistry.bundled())
        let entries = try await scanner.children(of: root)

        let link = try #require(entries.first { $0.name == "link-to-big" })
        #expect(link.sizeBytes == 0)
        #expect(!link.isDirectory)
    }
}
