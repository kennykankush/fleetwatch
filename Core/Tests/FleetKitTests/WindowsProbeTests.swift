import Foundation
import Testing
@testable import FleetKit

@Suite("Windows probe parser")
struct WindowsProbeTests {
    // Real output captured from magi (Windows 11, Ryzen 7 5700X, 32GB, no docker).
    static let realOutput = """
    ===OS===
    Microsoft Windows 11 Home
    10.0.26200.0
    ===CPU===
    16
    AMD Ryzen 7 5700X 8-Core Processor
    ===MEM===
    33474540 12508056
    ===DISK===
    998324412416 701890568192
    ===LOAD===
    7
    ===UPTIME===
    524163
    ===GPU===
    USB Mobile Monitor Virtual Display
    ===DOCKER===
    NO_DOCKER
    """

    @Test("Parses Windows hardware, trims CPU whitespace")
    func hardware() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(t.hardware.cores == 16)
        #expect(t.hardware.cpuModel == "AMD Ryzen 7 5700X 8-Core Processor")  // trailing spaces trimmed
        #expect(t.hardware.osName == "Microsoft Windows 11 Home")
        #expect(t.hardware.ramTotal == 33474540 * 1024)
    }

    @Test("Memory in KiB → bytes; available = free (no cache figure on Windows)")
    func memory() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(t.memTotal == 33474540 * 1024)
        #expect(t.memAvailable == 12508056 * 1024)
        #expect(t.memCached == 0)
        #expect(t.memUsed == (33474540 - 12508056) * 1024)
    }

    @Test("Disk bytes, and CPU load% normalized to a load-average shape")
    func diskLoad() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(t.diskTotal == 998324412416)
        #expect(t.diskFree == 701890568192)
        // 7% of 16 cores ≈ 1.12 load-equivalent.
        #expect(abs(t.load1 - 1.12) < 0.01)
        #expect(t.uptime == 524163)
    }

    @Test("No docker, no battery on this box")
    func capabilities() throws {
        let t = try #require(WindowsProbe.parse(Self.realOutput))
        #expect(!t.hasDocker)
        #expect(!t.hasBattery)
        #expect(t.containers.isEmpty)
    }

    @Test("CRLF line endings parse — PowerShell over SSH emits \\r\\n")
    func crlf() throws {
        let crlf = Self.realOutput.replacingOccurrences(of: "\n", with: "\r\n")
        let t = try #require(WindowsProbe.parse(crlf), "CRLF output must parse — this is what the real box sends")
        #expect(t.hardware.cores == 16)
        #expect(t.memTotal == 33474540 * 1024)
        #expect(t.diskTotal == 998324412416)
    }
}
