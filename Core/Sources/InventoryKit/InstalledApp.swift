import Foundation

/// Where an app came from — determines the correct uninstall path.
public enum AppSource: String, Codable, Sendable, CaseIterable, Hashable {
    /// Installed via `brew install --cask`; uninstalls with `brew uninstall --zap`.
    case homebrewCask
    /// A Homebrew formula (CLI tool); uninstalls with `brew uninstall`.
    case homebrewFormula
    /// Has a Mac App Store receipt; deletes cleanly by design.
    case appStore
    /// Downloaded directly; uninstall = app bundle + leftover sweep.
    case direct

    public var displayName: String {
        switch self {
        case .homebrewCask: "Homebrew Cask"
        case .homebrewFormula: "Homebrew CLI"
        case .appStore: "App Store"
        case .direct: "Direct install"
        }
    }
}

/// One entry in the Apps census.
public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: String { bundlePath }
    public let name: String
    public let bundlePath: String
    public let bundleIdentifier: String?
    public let source: AppSource
    /// nil while sizing is still in flight.
    public var sizeBytes: Int64?
    public let lastUsed: Date?

    public init(
        name: String,
        bundlePath: String,
        bundleIdentifier: String?,
        source: AppSource,
        sizeBytes: Int64?,
        lastUsed: Date?
    ) {
        self.name = name
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.source = source
        self.sizeBytes = sizeBytes
        self.lastUsed = lastUsed
    }
}
