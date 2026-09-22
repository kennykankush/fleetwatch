import Foundation

/// The last thing a machine told us about its size.
///
/// Persisted, because capacity is a property of the machine, not of the
/// network. magi owns 2 TB while it sleeps; a fleet total that drops when a
/// box powers down is measuring reachability, not strength.
public struct CapacitySnapshot: Codable, Sendable, Hashable {
    public var cores: Int
    public var ram: Int64
    public var storage: Int64
    public var storageUsed: Int64
    public var measured: Date

    public init(cores: Int, ram: Int64, storage: Int64, storageUsed: Int64, measured: Date = Date()) {
        self.cores = cores; self.ram = ram
        self.storage = storage; self.storageUsed = storageUsed
        self.measured = measured
    }

    /// Captures what a live probe just reported, summing every fixed volume.
    public init(_ t: MachineTelemetry, measured: Date = Date()) {
        self.cores = t.hardware.cores
        self.ram = t.hardware.ramTotal
        self.storage = t.disks.reduce(0) { $0 + $1.total }
        self.storageUsed = t.disks.reduce(0) { $0 + $1.used }
        self.measured = measured
    }
}

/// What the fleet *is* — the sum of everything you own, whether or not it
/// answers right now.
///
/// Two numbers, always both: **owned** is your total strength (live readings
/// where we have them, last-known where we don't, declared for cloud), and
/// **reachable** is the honest subset that answered this minute. Never one
/// number pretending to be the other.
public struct FleetStrength: Sendable, Hashable {
    /// A bundle of capacity. Cloud tallies carry storage only — a Drive plan
    /// has no cores, and inventing some would be exactly the kind of lie this
    /// app exists to refuse.
    public struct Tally: Sendable, Hashable {
        public var cores: Int = 0
        public var ram: Int64 = 0
        public var storage: Int64 = 0
        public var storageUsed: Int64 = 0

        public init(cores: Int = 0, ram: Int64 = 0, storage: Int64 = 0, storageUsed: Int64 = 0) {
            self.cores = cores; self.ram = ram
            self.storage = storage; self.storageUsed = storageUsed
        }

        public var storageFree: Int64 { max(0, storage - storageUsed) }
        public var storageUsedFraction: Double {
            storage > 0 ? min(1, Double(storageUsed) / Double(storage)) : 0
        }

        public static func + (a: Tally, b: Tally) -> Tally {
            Tally(cores: a.cores + b.cores, ram: a.ram + b.ram,
                  storage: a.storage + b.storage, storageUsed: a.storageUsed + b.storageUsed)
        }

        public static func += (a: inout Tally, b: Tally) { a = a + b }
    }

    /// Every machine, live or last-known.
    public var machines: Tally = .init()
    /// Only the machines that answered this cycle.
    public var machinesReachable: Tally = .init()
    /// Declared cloud capacity (storage only).
    public var cloud: Tally = .init()

    public var machineCount: Int = 0
    public var reachableCount: Int = 0
    public var cloudCount: Int = 0
    /// Cloud drives whose usage came from a probe rather than being typed in.
    public var cloudMeasuredCount: Int = 0
    /// Machines counted from a stored snapshot because they're unreachable.
    public var staleCount: Int = 0
    /// Machines in the fleet we have never successfully read — they can't be
    /// counted at all, and the UI should admit it rather than quietly omit it.
    public var unknownCount: Int = 0

    public var containers: Int = 0
    public var alerts: Int = 0

    /// Total strength: every machine plus every cloud drive.
    public var owned: Tally { machines + cloud }

    /// Storage you could actually touch this minute (local reachable only —
    /// cloud is excluded because reaching it depends on the provider, not on
    /// anything Fleetwatch measured).
    public var reachableStorage: Int64 { machinesReachable.storage }

    public var hasStaleData: Bool { staleCount > 0 }

    /// Builds the fleet's strength from everything the app knows.
    ///
    /// - Machines prefer live telemetry; an offline machine falls back to its
    ///   stored `CapacitySnapshot` and is counted as stale. One never seen at
    ///   all is counted as unknown and contributes nothing.
    /// - Cloud contributes declared capacity always, and usage only when known.
    public static func compute(
        machines list: [Machine],
        telemetry: [UUID: MachineTelemetry],
        capacities: [UUID: CapacitySnapshot],
        online: [UUID: Bool],
        clouds: [CloudDrive]
    ) -> FleetStrength {
        var s = FleetStrength()
        s.machineCount = list.count
        s.cloudCount = clouds.count

        for m in list {
            let isOnline = online[m.id] ?? (m.kind == .local)
            if isOnline, let t = telemetry[m.id] {
                let live = Tally(CapacitySnapshot(t))
                s.machines += live
                s.machinesReachable += live
                s.reachableCount += 1
                s.containers += t.containers.count
                if isAlerting(t) { s.alerts += 1 }
            } else if let snapshot = capacities[m.id] {
                s.machines += Tally(snapshot)
                s.staleCount += 1
            } else {
                s.unknownCount += 1
            }
        }

        for drive in clouds {
            s.cloud += Tally(storage: drive.capacity, storageUsed: drive.used ?? 0)
            if drive.isMeasured { s.cloudMeasuredCount += 1 }
        }

        return s
    }

    /// The fleet-grid warning rule: any vital past three-quarters.
    public static func isAlerting(_ t: MachineTelemetry) -> Bool {
        var worst = max(t.diskUsedFraction, t.memUsedFraction, min(t.loadFraction, 1))
        if t.swapPressured { worst = max(worst, t.swapUsedFraction) }
        return worst > 0.75
    }
}

extension FleetStrength.Tally {
    init(_ s: CapacitySnapshot) {
        self.init(cores: s.cores, ram: s.ram, storage: s.storage, storageUsed: s.storageUsed)
    }
}
