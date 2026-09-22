import Foundation

/// A cloud storage account that contributes capacity to the fleet.
///
/// Cloud drives are **declared, not discovered**. You own 4 TB of Google Drive
/// whether or not this Mac can reach it, and no macOS API will tell us the
/// plan size of an account — the sync clients mount through File Provider, so
/// `statfs` reports the local disk, not the quota. So the capacity is what you
/// say it is, and live usage is optional enrichment (see `CloudProbe`).
///
/// This mirrors how the app treats SSH: it never stores a credential. A
/// declared drive needs no auth at all; a measured one borrows the user's
/// existing `rclone` config.
public struct CloudDrive: Codable, Sendable, Identifiable, Hashable {
    public enum Provider: String, Codable, Sendable, CaseIterable, Identifiable {
        case googleDrive, oneDrive, dropbox, iCloud, box, mega, proton, s3, backblaze, other

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .googleDrive: "Google Drive"
            case .oneDrive: "OneDrive"
            case .dropbox: "Dropbox"
            case .iCloud: "iCloud Drive"
            case .box: "Box"
            case .mega: "MEGA"
            case .proton: "Proton Drive"
            case .s3: "S3"
            case .backblaze: "Backblaze"
            case .other: "Cloud storage"
            }
        }

        /// SF Symbol for the tile.
        public var symbol: String {
            switch self {
            case .s3, .backblaze: "externaldrive.badge.icloud"
            case .iCloud: "icloud"
            default: "cloud"
            }
        }
    }

    public let id: UUID
    public var name: String
    public var provider: Provider
    /// The plan ceiling — what you pay for. Declared.
    public var capacity: Int64
    /// Last known usage, declared or measured. `nil` = unknown, and the UI
    /// says so rather than drawing a zero.
    public var used: Int64?
    /// An `rclone` remote name (`gdrive:`) for live reads. Optional.
    public var rcloneRemote: String?
    /// When `used` was last measured by a probe. `nil` when hand-declared.
    public var lastMeasured: Date?

    public init(id: UUID = UUID(), name: String, provider: Provider,
                capacity: Int64, used: Int64? = nil,
                rcloneRemote: String? = nil, lastMeasured: Date? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.capacity = capacity
        self.used = used
        self.rcloneRemote = rcloneRemote
        self.lastMeasured = lastMeasured
    }

    public var free: Int64? {
        guard let used else { return nil }
        return max(0, capacity - used)
    }

    public var usedFraction: Double? {
        guard let used, capacity > 0 else { return nil }
        return min(1, Double(used) / Double(capacity))
    }

    /// True when usage came from a probe rather than being typed in.
    public var isMeasured: Bool { lastMeasured != nil }
}
