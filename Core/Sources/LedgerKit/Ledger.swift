import Foundation

/// One recorded moment: a measurement, or an action Fleetwatch took.
public struct LedgerEvent: Codable, Sendable, Identifiable, Hashable {
    public enum Kind: String, Codable, Sendable {
        /// A disk snapshot (taken at most once per app launch).
        case snapshot
        /// A startup item was disabled/enabled/removed.
        case startup
        /// Something was cleared (always to Trash, never rm).
        case cleared
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let title: String
    public let detail: String
    /// Bytes involved, when meaningful (snapshot = physical used; cleared = freed).
    public let bytes: Int64?
    /// Structured numbers for diffing between snapshots (older events: nil).
    public let metrics: [String: Int64]?

    public init(kind: Kind, title: String, detail: String, bytes: Int64? = nil, metrics: [String: Int64]? = nil) {
        self.id = UUID()
        self.date = .now
        self.kind = kind
        self.title = title
        self.detail = detail
        self.bytes = bytes
        self.metrics = metrics
    }
}

/// Append-only JSON ledger in Application Support. The app's memory:
/// every scan snapshot and every action, recoverable and reviewable.
public actor LedgerStore {
    /// The app-wide ledger in Application Support.
    public static let shared = LedgerStore()

    private let fileURL: URL
    private var cached: [LedgerEvent]?
    private var loaded = false

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Fleetwatch")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appending(path: "ledger.json")
        }
    }

    public func events() -> [LedgerEvent] {
        loadIfNeeded()
        return cached ?? []
    }

    /// Loads once. A file that exists but won't decode is QUARANTINED, never
    /// wiped — the corrupt bytes are moved aside so the next append writes a
    /// fresh file without destroying recoverable history (F-002).
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else {
            cached = []   // absent file — a clean first run, nothing to preserve
            return
        }
        if let events = try? Self.decoder.decode([LedgerEvent].self, from: data) {
            cached = events
        } else {
            quarantineCorruptFile()
            cached = []
        }
    }

    private func quarantineCorruptFile() {
        let fm = FileManager.default
        let stamp = Int(Date.now.timeIntervalSince1970)
        var dest = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        var n = 1
        while fm.fileExists(atPath: dest.path) {
            dest = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp)-\(n).json")
            n += 1
        }
        try? fm.moveItem(at: fileURL, to: dest)
    }

    @discardableResult
    public func append(_ event: LedgerEvent) -> [LedgerEvent] {
        var all = events()
        all.append(event)
        cached = all
        if let data = try? Self.encoder.encode(all) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return all
    }

    /// The most recent snapshot event, for diffing against the current scan.
    public func latestSnapshot() -> LedgerEvent? {
        events().last { $0.kind == .snapshot }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
