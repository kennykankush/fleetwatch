import Foundation

/// A machine's identity — static, scanned once on connect. CPU-Z-lite.
public struct HardwareInfo: Codable, Sendable, Hashable {
    public var cpuModel: String
    public var cores: Int
    public var ramTotal: Int64
    public var gpu: String?
    public var osName: String
    public var kernel: String

    public init(cpuModel: String, cores: Int, ramTotal: Int64, gpu: String?, osName: String, kernel: String) {
        self.cpuModel = cpuModel; self.cores = cores; self.ramTotal = ramTotal
        self.gpu = gpu; self.osName = osName; self.kernel = kernel
    }
}

/// One container on a machine running Docker — the homelab killer view.
public struct Container: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let status: String
    /// Best-effort health parsed from the status string.
    public var isHealthy: Bool { !status.lowercased().contains("unhealthy") && status.lowercased().hasPrefix("up") }

    public init(name: String, status: String) { self.name = name; self.status = status }
}

/// One storage volume on a machine (a drive letter or a mount point).
public struct DiskVolume: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String        // "C:", "D:", "/", "/data"
    public let total: Int64
    public let used: Int64
    public let free: Int64

    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public init(name: String, total: Int64, used: Int64, free: Int64) {
        self.name = name; self.total = total; self.used = used; self.free = free
    }
}

/// What Fleetwatch could read from a machine, plus what it's capable of — the
/// three-ring model made concrete. Universal fields are always present;
/// capabilities gate the Ring-2 organs.
public struct MachineTelemetry: Sendable, Hashable {
    public var hardware: HardwareInfo
    /// Every fixed volume, system disk first.
    public var disks: [DiskVolume]
    // Memory — bytes. `used` is honest (excludes reclaimable cache);
    // `available` counts cache as free (the purgeable lesson, on Linux).
    public var memTotal: Int64
    public var memUsed: Int64
    public var memAvailable: Int64
    public var memCached: Int64
    // CPU load averages.
    public var load1: Double
    public var load5: Double
    public var load15: Double
    public var uptime: TimeInterval
    // Ring-2 capabilities.
    public var hasDocker: Bool
    public var hasBattery: Bool
    public var containers: [Container]

    // Primary-volume conveniences.
    public var diskTotal: Int64 { disks.first?.total ?? 0 }
    public var diskUsed: Int64 { disks.first?.used ?? 0 }
    public var diskFree: Int64 { disks.first?.free ?? 0 }

    public var memUsedFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }
    public var diskUsedFraction: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }
    /// Load as a fraction of core count — a normalized "how busy" (can exceed 1).
    public var loadFraction: Double { hardware.cores > 0 ? load1 / Double(hardware.cores) : 0 }

    public init(hardware: HardwareInfo, disks: [DiskVolume],
                memTotal: Int64, memUsed: Int64, memAvailable: Int64, memCached: Int64,
                load1: Double, load5: Double, load15: Double, uptime: TimeInterval,
                hasDocker: Bool, hasBattery: Bool, containers: [Container]) {
        self.hardware = hardware
        self.disks = disks
        self.memTotal = memTotal; self.memUsed = memUsed; self.memAvailable = memAvailable; self.memCached = memCached
        self.load1 = load1; self.load5 = load5; self.load15 = load15; self.uptime = uptime
        self.hasDocker = hasDocker; self.hasBattery = hasBattery; self.containers = containers
    }
}
