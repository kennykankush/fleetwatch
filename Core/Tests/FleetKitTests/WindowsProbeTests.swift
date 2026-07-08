import Foundation
import Testing
@testable import FleetKit

@Suite("Windows probe parser")
struct WindowsProbeTests {
    // Real output captured from magi (Windows 11, Ryzen 7 5700X, 32GB, no
    // docker) — hardened MEM line: totalKB freeKB availableBytes standbyBytes.
    static let realOutput = """
    ===OS===
    Microsoft Windows 11 Home
    10.0.26200.0
    ===CPU===
    16
    AMD Ryzen 7 5700X 8-Core Processor
    ===MEM===
    33474540 12333784 12557271040 12548792320
    ===DISK===
    C: 998324412416 701890568192
    D: 2000381014016 1793117249536
    ===LOAD===
    7
    ===UPTIME===
    524163
    ===GPU===
    NVIDIA GeForce RTX 3070 Ti
    ===BATTERY===
    NO_BATTERY
    ===DOCKER===
    NO_DOCKER
    """

    @Test("Parses Windows hardware, trims CPU whitespace")
    func hardware() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(t.hardware.cores == 16)
        #expect(t.hardware.cpuModel == "AMD Ryzen 7 5700X 8-Core Processor")
        #expect(t.hardware.osName == "Microsoft Windows 11 Home")
        #expect(t.hardware.gpu == "NVIDIA GeForce RTX 3070 Ti")
        #expect(t.hardware.ramTotal == 33474540 * 1024)
    }

    @Test("Honest memory: available from perf counters, standby cache split out")
    func memoryHonest() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(t.memTotal == 33474540 * 1024)
        #expect(t.memAvailable == 12557271040)          // AvailableBytes
        #expect(t.memCached == 12548792320)             // standby cache — reclaimable
        #expect(t.memUsed == 33474540 * 1024 - 12557271040)  // total - available
    }

    @Test("Degrades to CIM-only when perf counters are absent")
    func memoryFallback() throws {
        let legacy = Self.realOutput.replacingOccurrences(
            of: "33474540 12333784 12557271040 12548792320",
            with: "33474540 12333784")
        let t = try #require(WindowsProbe.parse(legacy))
        #expect(t.memAvailable == 12333784 * 1024)
        #expect(t.memCached == 0)
    }

    @Test("ALL fixed drives detected — magi's 2TB D: was invisible before")
    func multiDisk() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(t.disks.count == 2)
        #expect(t.disks[0].name == "C:")             // system drive first
        #expect(t.disks[1].name == "D:")
        #expect(t.disks[1].total == 2000381014016)   // the mac-archives drive
        #expect(t.disks[1].free == 1793117249536)
    }

    @Test("Disk bytes, and CPU load% normalized to a load-average shape")
    func diskLoad() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(t.diskTotal == 998324412416)
        #expect(t.diskFree == 701890568192)
        #expect(abs(t.load1 - 1.12) < 0.01)   // 7% of 16 cores
        #expect(t.uptime == 524163)
    }

    @Test("Battery via Win32_Battery; docker absent on this box")
    func capabilities() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(!t.hasDocker)
        #expect(!t.hasBattery)
        let laptop = Self.realOutput.replacingOccurrences(of: "NO_BATTERY", with: "BAT")
        #expect(try #require(WindowsProbe.parse(laptop)).hasBattery)
    }

    @Test("CRLF line endings parse — PowerShell over SSH emits \\r\\n")
    func crlf() throws {
        let crlf = Self.realOutput.replacingOccurrences(of: "\n", with: "\r\n")
        let t = try #require(WindowsProbe.parse(crlf))
        #expect(t.hardware.cores == 16)
        #expect(t.memCached == 12548792320)
    }
}
