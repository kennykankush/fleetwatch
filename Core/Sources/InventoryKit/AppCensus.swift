import Foundation

/// Collects the totality of installed software, classified by source.
///
/// Fast phase: enumerate bundles and classify (no sizing). Sizes are
/// measured separately so the UI can show the census immediately and let
/// sizes stream in.
public struct AppCensus: Sendable {
    public let brew: BrewCatalog

    public init(brew: BrewCatalog = .local()) {
        self.brew = brew
    }

    /// All .app bundles in /Applications and ~/Applications (one folder level
    /// deep, so "DaVinci Resolve/DaVinci Resolve.app" is found), classified.
    /// Sizes are nil — measure them separately.
    public func collectApps() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            fm.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]

        var bundles: [URL] = []
        for root in roots {
            guard let children = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for child in children {
                if child.pathExtension == "app" {
                    bundles.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    let nested = (try? fm.contentsOfDirectory(
                        at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                    )) ?? []
                    bundles.append(contentsOf: nested.filter { $0.pathExtension == "app" })
                }
            }
        }

        return bundles.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            return InstalledApp(
                name: name,
                bundlePath: url.path,
                bundleIdentifier: Bundle(url: url)?.bundleIdentifier,
                source: classify(bundleURL: url, name: name),
                sizeBytes: nil,
                lastUsed: Self.lastUsedDate(of: url)
            )
        }
    }

    /// Homebrew CLI formulae as census entries (Cellar directory = "bundle").
    public func collectFormulae() -> [InstalledApp] {
        brew.formulae.map { name, cellarDir in
            InstalledApp(
                name: name,
                bundlePath: cellarDir.path,
                bundleIdentifier: nil,
                source: .homebrewFormula,
                sizeBytes: nil,
                lastUsed: nil
            )
        }
    }

    private func classify(bundleURL: URL, name: String) -> AppSource {
        let receipt = bundleURL.appending(path: "Contents/_MASReceipt/receipt")
        if FileManager.default.fileExists(atPath: receipt.path) {
            return .appStore
        }
        if brew.caskToken(matchingAppNamed: name) != nil {
            return .homebrewCask
        }
        return .direct
    }

    /// Spotlight's "last used" date, when available.
    private static func lastUsedDate(of url: URL) -> Date? {
        guard let item = NSMetadataItem(url: url) else { return nil }
        return item.value(forAttribute: "kMDItemLastUsedDate") as? Date
    }
}
