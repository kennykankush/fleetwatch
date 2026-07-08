import Foundation
import Testing
@testable import FleetKit

@Suite("Linux probe parser")
struct LinuxProbeTests {
    // Real output captured from hadi-pc (Ubuntu 24.04, Ryzen 5 5625U, 16GB,
    // 13 docker containers, a battery). The parser must survive real data.
    static let realOutput = """
    ===OS===
    Ubuntu 24.04.4 LTS
    6.17.0-20-generic
    ===CPU===
    12
    AMD Ryzen 5 5625U with Radeon Graphics
    ===LOAD===
    0.18 0.20 0.16 2/1749 3131915
    ===MEM===
    Mem:     16070844416  9038823424  1167216640   208424960  6416908288  7032020992
    ===DISK===
    / 501809635328 116446396416 359797436416
    ===UPTIME===
    8034162.11
    ===DOCKER===
    bank-browser-dbs|Up 7 days
    docs-reader|Up 3 months
    media-stack-jellyfin-1|Up 3 months (healthy)
    gitea|Up 2 months
    ===BATTERY===
    BAT0
    ===GPU===
    Advanced Micro Devices, Inc. [AMD/ATI] Barcelo (rev c2)
    """

    @Test("Parses hardware identity from real output")
    func hardware() throws {
        let t = try #require(LinuxProbe.parse(Self.realOutput))
        #expect(t.hardware.cores == 12)
        #expect(t.hardware.cpuModel == "AMD Ryzen 5 5625U with Radeon Graphics")
        #expect(t.hardware.osName == "Ubuntu 24.04.4 LTS")
        #expect(t.hardware.kernel == "6.17.0-20-generic")
        #expect(t.hardware.gpu?.contains("AMD") == true)
        #expect(t.hardware.ramTotal == 16070844416)
    }

    @Test("Memory is the honest story: used excludes cache, available counts it")
    func memory() throws {
        let t = try #require(LinuxProbe.parse(Self.realOutput))
        #expect(t.memTotal == 16070844416)
        #expect(t.memUsed == 9038823424)          // honest used
        #expect(t.memAvailable == 7032020992)     // cache counted as free
        #expect(t.memCached == 6416908288)        // the reclaimable gap
        // Naive "used" (total - free) would be far higher than honest used.
        #expect(t.memUsed < t.memTotal - t.memAvailable + t.memCached)
    }

    @Test("Disk and load parse")
    func diskLoad() throws {
        let t = try #require(LinuxProbe.parse(Self.realOutput))
        #expect(t.diskTotal == 501809635328)
        #expect(t.diskUsed == 116446396416)
        #expect(t.load1 == 0.18)
        #expect(t.load15 == 0.16)
        #expect(t.uptime > 8_000_000)
    }

    @Test("Docker + battery capabilities detected, containers parsed")
    func capabilities() throws {
        let t = try #require(LinuxProbe.parse(Self.realOutput))
        #expect(t.hasDocker)
        #expect(t.hasBattery)
        #expect(t.containers.count == 4)
        #expect(t.containers.contains { $0.name == "gitea" })
        let jellyfin = try #require(t.containers.first { $0.name.contains("jellyfin") })
        #expect(jellyfin.isHealthy)
    }

    @Test("No-docker / no-battery boxes degrade cleanly")
    func absentCapabilities() throws {
        let minimal = """
        ===OS===
        Debian
        6.1.0
        ===CPU===
        4
        Intel Xeon
        ===LOAD===
        1.5 1.2 1.0
        ===MEM===
        Mem: 8000000000 2000000000 1000000000 100000000 5000000000 6000000000
        ===DISK===
        / 100000000000 50000000000 50000000000
        ===UPTIME===
        3600
        ===DOCKER===
        NO_DOCKER
        ===BATTERY===
        NO_BATTERY
        ===GPU===
        NO_GPU
        """
        let t = try #require(LinuxProbe.parse(minimal))
        #expect(!t.hasDocker)
        #expect(!t.hasBattery)
        #expect(t.containers.isEmpty)
        #expect(t.hardware.gpu == nil)
    }
}
