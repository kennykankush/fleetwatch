import Foundation

/// One recorded moment: a measurement, or an action Stockpile took.
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

    public init(kind: Kind, title: String, detail: String, bytes: Int64? = nil) {
        self.id = UUID()
        self.date = .now
        self.kind = kind
        self.title = title
        self.detail = detail
        self.bytes = bytes
    }
}

/// Append-only JSON ledger in Application Support. The app's memory:
/// every scan snapshot and every action, recoverable and reviewable.
public actor LedgerStore {
    /// The app-wide ledger in Application Support.
    public static let shared = LedgerStore()

    private let fileURL: URL
    private var cached: [LedgerEvent]?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Stockpile")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appending(path: "ledger.json")
        }
    }

    public func events() -> [LedgerEvent] {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? Self.decoder.decode([LedgerEvent].self, from: data)
        else {
            cached = []
            return []
        }
        cached = events
        return events
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
