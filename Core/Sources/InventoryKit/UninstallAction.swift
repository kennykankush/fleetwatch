import Foundation
import ScannerKit

/// A leftover an app scattered outside its bundle.
public struct Leftover: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let sizeBytes: Int64
}

/// Finds the standard places apps leave residue — the manual sweep from
/// the housekeeping session that birthed this app, as a function. Same
/// spirit as a cask's `zap trash:` stanza.
public enum LeftoverLocator {
    public static func find(
        bundleIdentifier: String?,
        appName: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [Leftover] {
        var relative: [String] = [
            "Library/Application Support/\(appName)",
            "Library/Logs/\(appName)",
            "Library/Caches/\(appName)",
        ]
        if let id = bundleIdentifier {
            relative += [
                "Library/Caches/\(id)",
                "Library/Preferences/\(id).plist",
                "Library/Saved Application State/\(id).savedState",
                "Library/HTTPStorages/\(id)",
                "Library/WebKit/\(id)",
                "Library/Application Support/\(id)",
            ]
        }

        let fm = FileManager.default
        var seen = Set<String>()
        return relative.compactMap { rel in
            let url = home.appending(path: rel)
            guard fm.fileExists(atPath: url.path), seen.insert(url.path).inserted else { return nil }
            return Leftover(path: url.path, sizeBytes: AllocatedSize.measure(url))
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

/// Source-aware uninstall: the correct removal path per origin, Trash-only
/// for anything Stockpile deletes itself.
public enum UninstallAction {
    /// Returns a plain-words description for the Ledger.
    public static func uninstall(_ app: InstalledApp, leftovers: [Leftover], brew: BrewCatalog) throws -> String {
        switch app.source {
        case .homebrewCask:
            guard let token = brew.caskToken(matchingAppNamed: app.name),
                  let brewBin = brewExecutable() else {
                // Fall back to the manual path if the token vanished.
                return try manualUninstall(app, leftovers: leftovers)
            }
            let output = run(brewBin, ["uninstall", "--cask", "--zap", token])
            guard output != nil else { throw UninstallError.brewFailed(token) }
            // brew --zap covers its declared paths; sweep anything left.
            let remaining = leftovers.filter { FileManager.default.fileExists(atPath: $0.path) }
            for leftover in remaining {
                _ = try? TrashAction.moveToTrash(path: leftover.path)
            }
            return "Uninstalled \(app.name) via brew uninstall --zap \(token)"

        case .homebrewFormula:
            guard let brewBin = brewExecutable(),
                  run(brewBin, ["uninstall", app.name]) != nil else {
                throw UninstallError.brewFailed(app.name)
            }
            return "Uninstalled formula \(app.name) via brew"

        case .appStore, .direct:
            return try manualUninstall(app, leftovers: leftovers)
        }
    }

    private static func manualUninstall(_ app: InstalledApp, leftovers: [Leftover]) throws -> String {
        try TrashAction.moveToTrash(path: app.bundlePath)
        var swept = 0
        for leftover in leftovers where FileManager.default.fileExists(atPath: leftover.path) {
            if (try? TrashAction.moveToTrash(path: leftover.path)) != nil { swept += 1 }
        }
        return "Uninstalled \(app.name) — app and \(swept) leftover location\(swept == 1 ? "" : "s") moved to Trash"
    }

    private static func brewExecutable() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    private static func run(_ tool: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        } catch {
            return nil
        }
    }

    public enum UninstallError: Error, LocalizedError {
        case brewFailed(String)

        public var errorDescription: String? {
            switch self {
            case .brewFailed(let name): "brew uninstall failed for \(name)"
            }
        }
    }
}
