import Foundation
import Testing
@testable import RulesKit

@Suite("Rules registry")
struct RulesRegistryTests {
    @Test("Bundled registry loads and is non-trivial")
    func bundledLoads() throws {
        let registry = try RulesRegistry.bundled()
        #expect(registry.version >= 1)
        #expect(registry.rules.count >= 15)
        // Every rule speaks plain words, never bare identifiers.
        for rule in registry.rules {
            #expect(!rule.title.isEmpty)
            #expect(!rule.explanation.isEmpty)
            #expect(!rule.regeneration.isEmpty)
        }
    }

    @Test("node_modules matches only beside a package.json")
    func nodeModulesNeedsSibling() throws {
        let registry = try RulesRegistry.bundled()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "stockpile-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        // A real JS project: node_modules beside package.json.
        let project = root.appending(path: "project")
        try fm.createDirectory(at: project.appending(path: "node_modules"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appending(path: "package.json"))

        // An impostor: a folder someone named node_modules with no project around it.
        let impostor = root.appending(path: "photos/node_modules")
        try fm.createDirectory(at: impostor, withIntermediateDirectories: true)

        let matched = registry.match(directoryAt: project.appending(path: "node_modules"))
        #expect(matched?.id == "node-modules")
        #expect(matched?.tier == .regenerable)

        #expect(registry.match(directoryAt: impostor) == nil)
    }

    @Test(".venv requires pyvenv.cfg inside")
    func venvNeedsChild() throws {
        let registry = try RulesRegistry.bundled()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "stockpile-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let realVenv = root.appending(path: "a/.venv")
        try fm.createDirectory(at: realVenv, withIntermediateDirectories: true)
        try Data("home = /usr/bin".utf8).write(to: realVenv.appending(path: "pyvenv.cfg"))

        let fakeVenv = root.appending(path: "b/.venv")
        try fm.createDirectory(at: fakeVenv, withIntermediateDirectories: true)

        #expect(registry.match(directoryAt: realVenv)?.id == "python-venv")
        #expect(registry.match(directoryAt: fakeVenv) == nil)
    }

    @Test("Home-relative paths match exactly, not by prefix")
    func homeRelativeExactMatch() throws {
        let registry = try RulesRegistry.bundled()
        let home = URL(fileURLWithPath: "/Users/example")

        let spotify = home.appending(path: "Library/Caches/com.spotify.client")
        #expect(registry.match(directoryAt: spotify, home: home)?.id == "spotify-cache")

        // A subfolder of a matched path is NOT itself a match.
        let inside = spotify.appending(path: "Storage")
        #expect(registry.match(directoryAt: inside, home: home) == nil)
    }

    @Test("Unknown directories are user data — never matched")
    func unknownIsUntouchable() throws {
        let registry = try RulesRegistry.bundled()
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(registry.match(directoryAt: home.appending(path: "Desktop/guitarmix"), home: home) == nil)
        #expect(registry.match(directoryAt: home.appending(path: "dev/fantopy-hadi"), home: home) == nil)
    }
}
