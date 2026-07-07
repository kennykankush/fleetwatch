import Foundation

/// What Homebrew knows: installed cask tokens and formula names.
public struct BrewCatalog: Sendable {
    public let caskTokens: Set<String>
    /// Formula name → Cellar directory.
    public let formulae: [String: URL]
    public let cellarURL: URL?

    public static let empty = BrewCatalog(caskTokens: [], formulae: [:], cellarURL: nil)

    public init(caskTokens: Set<String>, formulae: [String: URL], cellarURL: URL?) {
        self.caskTokens = caskTokens
        self.formulae = formulae
        self.cellarURL = cellarURL
    }

    /// Reads the local Homebrew installation directly from disk — no `brew`
    /// subprocess, so it's fast and works even if brew's shell env is odd.
    public static func local() -> BrewCatalog {
        let candidates = ["/opt/homebrew", "/usr/local"]
        guard let prefix = candidates.first(where: {
            FileManager.default.fileExists(atPath: "\($0)/bin/brew")
        }) else { return .empty }

        let fm = FileManager.default

        let caskroom = URL(fileURLWithPath: "\(prefix)/Caskroom")
        let casks = (try? fm.contentsOfDirectory(atPath: caskroom.path)) ?? []

        let cellar = URL(fileURLWithPath: "\(prefix)/Cellar")
        let formulaNames = (try? fm.contentsOfDirectory(atPath: cellar.path)) ?? []
        var formulae: [String: URL] = [:]
        for name in formulaNames where !name.hasPrefix(".") {
            formulae[name] = cellar.appending(path: name)
        }

        return BrewCatalog(
            caskTokens: Set(casks.filter { !$0.hasPrefix(".") }),
            formulae: formulae,
            cellarURL: cellar
        )
    }

    /// Matches an app bundle name ("Visual Studio Code") against cask tokens
    /// ("visual-studio-code") by comparing normalized forms.
    public func caskToken(matchingAppNamed name: String) -> String? {
        let target = Self.normalize(name)
        return caskTokens.first { Self.normalize($0) == target }
    }

    /// Lowercased alphanumerics only: "Visual Studio Code" == "visual-studio-code".
    public static func normalize(_ s: String) -> String {
        s.lowercased().filter(\.isAlphanumeric)
    }
}

private extension Character {
    var isAlphanumeric: Bool { isLetter || isNumber }
}
