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

/// What Fleetwatch could read from a machine, plus what it's capable of — the
/// three-ring model made concrete. Universal fields are always present;
/// capabilities gate the Ring-2 organs.
public struct MachineTelemetry: Sendable, Hashable {
    public var hardware: HardwareInfo
    // Disk (root volume) — bytes.
    public var diskTotal: Int64
    public var diskUsed: Int64
    public var diskFree: Int64
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

    public var memUsedFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }
    public var diskUsedFraction: Double { diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0 }
    /// Load as a fraction of core count — a normalized "how busy" (can exceed 1).
    public var loadFraction: Double { hardware.cores > 0 ? load1 / Double(hardware.cores) : 0 }

    public init(hardware: HardwareInfo, diskTotal: Int64, diskUsed: Int64, diskFree: Int64,
                memTotal: Int64, memUsed: Int64, memAvailable: Int64, memCached: Int64,
                load1: Double, load5: Double, load15: Double, uptime: TimeInterval,
                hasDocker: Bool, hasBattery: Bool, containers: [Container]) {
        self.hardware = hardware
        self.diskTotal = diskTotal; self.diskUsed = diskUsed; self.diskFree = diskFree
        self.memTotal = memTotal; self.memUsed = memUsed; self.memAvailable = memAvailable; self.memCached = memCached
        self.load1 = load1; self.load5 = load5; self.load15 = load15; self.uptime = uptime
        self.hasDocker = hasDocker; self.hasBattery = hasBattery; self.containers = containers
    }
}
