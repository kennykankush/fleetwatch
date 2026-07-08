import Foundation

/// Both truths about a volume, side by side.
///
/// `physical` counts actual bytes on disk (what `df` reports). `effective`
/// additionally treats purgeable space — caches macOS will auto-delete under
/// pressure — as free (what Finder and modern widgets report). Fleetwatch
/// always shows both; a meter that silently switches between them is how this
/// app got born.
public struct DiskAccounting: Sendable, Equatable {
    public let volumeURL: URL
    public let totalCapacity: Int64
    /// Strict free space — bytes not occupied by anything.
    public let physicalFree: Int64
    /// Free space counting purgeable as already free (importantUsage).
    public let effectiveFree: Int64

    public var physicalUsed: Int64 { totalCapacity - physicalFree }
    public var effectiveUsed: Int64 { totalCapacity - effectiveFree }
    /// Space macOS has promised it can reclaim automatically.
    public var purgeable: Int64 { max(0, effectiveFree - physicalFree) }

    public var physicalUsedFraction: Double {
        totalCapacity > 0 ? Double(physicalUsed) / Double(totalCapacity) : 0
    }
    public var effectiveUsedFraction: Double {
        totalCapacity > 0 ? Double(effectiveUsed) / Double(totalCapacity) : 0
    }

    public init(volumeURL: URL, totalCapacity: Int64, physicalFree: Int64, effectiveFree: Int64) {
        self.volumeURL = volumeURL
        self.totalCapacity = totalCapacity
        self.physicalFree = physicalFree
        self.effectiveFree = effectiveFree
    }

    /// Measures the volume containing `url` (defaults to the boot volume).
    public static func measure(volumeAt url: URL = URL(fileURLWithPath: "/")) throws -> DiskAccounting {
        let values = try url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard
            let total = values.volumeTotalCapacity,
            let strict = values.volumeAvailableCapacity,
            let important = values.volumeAvailableCapacityForImportantUsage
        else {
            throw AccountingError.unavailable
        }
        return DiskAccounting(
            volumeURL: url,
            totalCapacity: Int64(total),
            physicalFree: Int64(strict),
            effectiveFree: important
        )
    }

    public enum AccountingError: Error {
        case unavailable
    }
}
