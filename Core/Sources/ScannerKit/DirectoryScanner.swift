import Foundation
import RulesKit

/// One row in a Descend view: a child of the directory being inspected,
/// sized and annotated.
public struct ScannedEntry: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    /// Allocated bytes on disk (not logical size — APFS clones and sparse
    /// files report what they actually occupy).
    public let sizeBytes: Int64
    /// The matched rule, if Stockpile recognizes this entry. nil = user data.
    public let rule: Rule?
}

/// Sizes the children of a directory concurrently and annotates each against
/// the rules registry.
///
/// Sizing counts *allocated* size, never follows symlinks, and never reads
/// file contents (so iCloud dataless files are not downloaded by scanning).
public struct DirectoryScanner: Sendable {
    private let registry: RulesRegistry

    public init(registry: RulesRegistry) {
        self.registry = registry
    }

    /// Returns the immediate children of `url`, sized recursively, largest first.
    public func children(of url: URL) async throws -> [ScannedEntry] {
        let fm = FileManager.default
        let childURLs = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )

        return await withTaskGroup(of: ScannedEntry?.self) { group in
            for child in childURLs {
                group.addTask {
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    let isSymlink = values?.isSymbolicLink ?? false
                    let isDirectory = (values?.isDirectory ?? false) && !isSymlink
                    let size = AllocatedSize.measure(child)
                    return ScannedEntry(
                        url: child,
                        name: child.lastPathComponent,
                        isDirectory: isDirectory,
                        sizeBytes: size,
                        rule: isDirectory ? self.registry.match(directoryAt: child) : nil
                    )
                }
            }
            var entries: [ScannedEntry] = []
            for await entry in group {
                if let entry { entries.append(entry) }
            }
            return entries.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

}
