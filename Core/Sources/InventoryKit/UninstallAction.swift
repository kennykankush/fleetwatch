import Foundation
import ScannerKit

/// A leftover an app scattered outside its bundle.
public struct Leftover: Sendable, Identifiable, Hashable {
    /// How sure we are this path belongs to the app.
    /// `high` — derived from the globally-unique bundle identifier; safe to sweep.
    /// `low`  — derived from the display name, which can collide with shared
    ///          directories (e.g. `~/Library/Application Support/Electron`).
    ///          Surfaced for review, NEVER swept automatically.
    public enum Confidence: String, Sendable, Hashable {
        case high, low
    }

    public var id: String { path }
    public let path: String
    public let sizeBytes: Int64
    public let confidence: Confidence

    public init(path: String, sizeBytes: Int64, confidence: Confidence) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.confidence = confidence
    }
}

/// Finds the standard places apps leave residue — the manual sweep from
/// the housekeeping session that birthed this app, as a function. Same
/// spirit as a cask's `zap trash:` stanza.
///
/// Ownership safety: bundle-identifier paths (reverse-DNS, globally unique)
/// are `high` confidence. Display-name paths can collide with directories
/// shared by many apps, so they are `low` confidence — shown for review but
/// never auto-deleted. This is the guard against uninstalling one app and
/// trashing another's data (F-001).
public enum LeftoverLocator {
    public static func find(
        bundleIdentifier: String?,
        appName: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [Leftover] {
        // Bundle-ID paths — unique, safe to sweep.
        var highPaths: [String] = []
        if let id = bundleIdentifier, isDistinctiveBundleID(id) {
            highPaths = [
                "Library/Caches/\(id)",
                "Library/Preferences/\(id).plist",
                "Library/Saved Application State/\(id).savedState",
                "Library/HTTPStorages/\(id)",
                "Library/WebKit/\(id)",
                "Library/Application Support/\(id)",
                "Library/Containers/\(id)",
                "Library/Group Containers/\(id)",
            ]
        }
        // Display-name paths — can collide; review-only.
        let lowPaths = [
            "Library/Application Support/\(appName)",
            "Library/Logs/\(appName)",
            "Library/Caches/\(appName)",
        ]

        let fm = FileManager.default
        var seen = Set<String>()
        func collect(_ relatives: [String], _ confidence: Leftover.Confidence) -> [Leftover] {
            relatives.compactMap { rel -> Leftover? in
                let url = home.appending(path: rel)
                guard fm.fileExists(atPath: url.path), seen.insert(url.path).inserted else { return nil }
                return Leftover(path: url.path, sizeBytes: AllocatedSize.measure(url), confidence: confidence)
            }
        }

        return (collect(highPaths, .high) + collect(lowPaths, .low))
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// A real reverse-DNS bundle id has at least two dot-separated segments.
    /// Guards against a bare or malformed id producing dangerous wide paths.
    private static func isDistinctiveBundleID(_ id: String) -> Bool {
        let parts = id.split(separator: ".")
        return parts.count >= 2 && !id.hasSuffix(".") && !id.hasPrefix(".")
    }
}

/// Source-aware uninstall: the correct removal path per origin, Trash-only
/// for anything Fleetwatch deletes itself.
public enum UninstallAction {
    /// The result of an uninstall, so the UI can tell the user exactly what
    /// happened — including what was deliberately left for review.
    public struct Outcome: Sendable {
        public let description: String
        public let leftForReview: [Leftover]
    }

    /// Uninstalls, sweeping only `high`-confidence leftovers. `low`-confidence
    /// (name-matched) leftovers are returned in `leftForReview`, never deleted.
    public static func uninstall(_ app: InstalledApp, leftovers: [Leftover], brew: BrewCatalog) throws -> Outcome {
        let sweepable = leftovers.filter { $0.confidence == .high }
        let review = leftovers.filter { $0.confidence == .low && FileManager.default.fileExists(atPath: $0.path) }

        switch app.source {
        case .homebrewCask:
            // Verify the cask actually owns THIS install before running --zap
            // on a name-matched token (F-007).
            guard let token = brew.caskToken(matchingAppNamed: app.name),
                  let brewBin = brewExecutable(),
                  caskOwns(app: app, token: token, brewBin: brewBin) else {
                return try manualUninstall(app, sweepable: sweepable, review: review)
            }
            guard run(brewBin, ["uninstall", "--cask", "--zap", token]) != nil else {
                throw UninstallError.brewFailed(token)
            }
            for leftover in sweepable where FileManager.default.fileExists(atPath: leftover.path) {
                _ = try? TrashAction.moveToTrash(path: leftover.path)
            }
            return Outcome(
                description: "Uninstalled \(app.name) via brew uninstall --zap \(token)",
                leftForReview: review
            )

        case .homebrewFormula:
            guard let brewBin = brewExecutable(),
                  run(brewBin, ["uninstall", app.name]) != nil else {
                throw UninstallError.brewFailed(app.name)
            }
            return Outcome(description: "Uninstalled formula \(app.name) via brew", leftForReview: [])

        case .appStore, .direct:
            return try manualUninstall(app, sweepable: sweepable, review: review)
        }
    }

    private static func manualUninstall(_ app: InstalledApp, sweepable: [Leftover], review: [Leftover]) throws -> Outcome {
        try TrashAction.moveToTrash(path: app.bundlePath)
        var swept = 0
        for leftover in sweepable where FileManager.default.fileExists(atPath: leftover.path) {
            if (try? TrashAction.moveToTrash(path: leftover.path)) != nil { swept += 1 }
        }
        let reviewNote = review.isEmpty ? "" : " · \(review.count) name-matched location\(review.count == 1 ? "" : "s") left for review"
        return Outcome(
            description: "Uninstalled \(app.name) — app + \(swept) leftover\(swept == 1 ? "" : "s") to Trash\(reviewNote)",
            leftForReview: review
        )
    }

    /// Confirms the cask's installed artifact is actually this app bundle,
    /// so a name-collision can't point `--zap` at the wrong software.
    private static func caskOwns(app: InstalledApp, token: String, brewBin: String) -> Bool {
        guard let listing = run(brewBin, ["list", "--cask", token]) else { return false }
        let appFileName = URL(fileURLWithPath: app.bundlePath).lastPathComponent
        // brew list --cask prints the installed artifact paths/names.
        return listing.contains(appFileName)
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
