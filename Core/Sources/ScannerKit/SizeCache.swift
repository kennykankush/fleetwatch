import Foundation

/// Persistent, mtime-validated size cache — the reason Fleetwatch stays cheap.
///
/// Policy: a measurement is trusted while the entry's modification time is
/// unchanged, or until the user refreshes. Directory mtimes only change on
/// direct-child mutations, so deep changes can go stale — the UI shows
/// `measuredAt` honestly and Refresh invalidates the whole subtree. Cheap,
/// honest, and never silently wrong about *when* it measured.
///
/// The cache is LRU-capped so it cannot itself become bloat, and it drops its
/// in-memory copy under system memory pressure (the disk copy remains).
public actor SizeCache {
    public static let shared = SizeCache()

    public struct Entry: Codable, Sendable {
        public let size: Int64
        public let mtime: TimeInterval
        public let measuredAt: Date
    }

    private var entries: [String: Entry] = [:]
    /// Memoized path→canonical resolution so canonicalization costs one
    /// filesystem walk per unique path per session, not one per lookup —
    /// preserving instant warm revisits.
    private var canonMemo: [String: String] = [:]
    private var loaded = false
    private var dirty = false
    private let fileURL: URL
    private let maxEntries: Int

    public init(fileURL: URL? = nil, maxEntries: Int = 40_000) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Fleetwatch")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appending(path: "sizecache.json")
        }
        self.maxEntries = maxEntries
    }

    /// Returns a trusted entry, or nil if unknown / mtime changed.
    public func lookup(path: String, mtime: TimeInterval) -> Entry? {
        loadIfNeeded()
        guard let entry = entries[key(path)], entry.mtime == mtime else { return nil }
        return entry
    }

    public func store(path: String, mtime: TimeInterval, size: Int64) {
        loadIfNeeded()
        entries[key(path)] = Entry(size: size, mtime: mtime, measuredAt: .now)
        dirty = true
        if entries.count > maxEntries {
            evictOldest(keeping: maxEntries * 3 / 4)
        }
    }

    /// Forget everything under a path (inclusive) — the Refresh/clear action.
    public func invalidate(subtree path: String) {
        loadIfNeeded()
        let canonical = key(path)
        let prefix = canonical.hasSuffix("/") ? canonical : canonical + "/"
        entries = entries.filter { $0.key != canonical && !$0.key.hasPrefix(prefix) }
        dirty = true
    }

    /// Canonical cache key: resolves symlink aliases (and /var → /private/var)
    /// so the same directory reached by different paths shares one entry, and
    /// an invalidation through any alias clears it (F-003). Memoized so the
    /// filesystem walk happens once per unique path, not per lookup.
    private func key(_ path: String) -> String {
        if let hit = canonMemo[path] { return hit }
        let canonical = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        canonMemo[path] = canonical
        return canonical
    }

    /// Write to disk if anything changed. Call after a scan batch, not per-entry.
    public func flush() {
        guard dirty else { return }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
            dirty = false
        }
    }

    /// Drop the in-memory copy (disk copy stays). Wired to memory pressure.
    public func releaseMemory() {
        flush()
        entries = [:]
        canonMemo = [:]
        loaded = false
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = stored
    }

    private func evictOldest(keeping target: Int) {
        let sorted = entries.sorted { $0.value.measuredAt > $1.value.measuredAt }
        entries = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(target)))
    }
}
