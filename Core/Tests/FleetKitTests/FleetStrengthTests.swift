import Foundation
import Testing
@testable import FleetKit

@Suite("Fleet strength")
struct FleetStrengthTests {
    // A 4-core / 16 GB box with a 500 GB disk, half full.
    static func telemetry(cores: Int = 4, ram: Int64 = 16_000_000_000,
                          disks: [DiskVolume] = [DiskVolume(name: "/", total: 500_000_000_000,
                                                            used: 250_000_000_000, free: 250_000_000_000)],
                          containers: [Container] = []) -> MachineTelemetry {
        MachineTelemetry(
            hardware: HardwareInfo(cpuModel: "Test CPU", cores: cores, ramTotal: ram,
                                   gpu: nil, osName: "TestOS", kernel: "1.0"),
            disks: disks,
            memTotal: ram, memUsed: ram / 2, memAvailable: ram / 2, memCached: 0,
            load1: 0.1, load5: 0.1, load15: 0.1, uptime: 3600,
            hasDocker: !containers.isEmpty, hasBattery: false, containers: containers
        )
    }

    @Test("Owned strength counts an offline machine from its last-known snapshot")
    func offlineStillCounts() {
        let mac = Machine.thisMac(name: "Mac")
        let magi = Machine(name: "magi", kind: .remote, host: "magi", user: "hadim", os: .windows)

        // magi is off, but we measured it before: 8 cores, 32 GB, 2 TB.
        let stored = CapacitySnapshot(cores: 8, ram: 32_000_000_000,
                                      storage: 2_000_000_000_000, storageUsed: 400_000_000_000)

        let s = FleetStrength.compute(
            machines: [mac, magi],
            telemetry: [mac.id: Self.telemetry()],
            capacities: [magi.id: stored],
            online: [mac.id: true, magi.id: false],
            clouds: []
        )

        // Owned = both machines. Reachable = only the Mac.
        #expect(s.machines.cores == 12)
        #expect(s.machines.ram == 48_000_000_000)
        #expect(s.machines.storage == 2_500_000_000_000)
        #expect(s.machinesReachable.cores == 4)
        #expect(s.machinesReachable.storage == 500_000_000_000)
        #expect(s.reachableCount == 1)
        #expect(s.staleCount == 1)
        #expect(s.hasStaleData)
    }

    @Test("A machine never successfully read is unknown, not silently zero")
    func neverSeenIsUnknown() {
        let ghost = Machine(name: "ghost", kind: .remote, host: "ghost", user: "x", os: .unknown)
        let s = FleetStrength.compute(machines: [ghost], telemetry: [:], capacities: [:],
                                      online: [ghost.id: false], clouds: [])
        #expect(s.unknownCount == 1)
        #expect(s.staleCount == 0)
        #expect(s.machines.storage == 0)
        #expect(s.machineCount == 1)
    }

    @Test("Cloud adds storage but never fabricates cores or RAM")
    func cloudIsStorageOnly() {
        let mac = Machine.thisMac(name: "Mac")
        let drive = CloudDrive(name: "Google Drive", provider: .googleDrive,
                               capacity: 4_000_000_000_000, used: 256_000_000_000)

        let s = FleetStrength.compute(machines: [mac], telemetry: [mac.id: Self.telemetry()],
                                      capacities: [:], online: [mac.id: true], clouds: [drive])

        #expect(s.cloud.storage == 4_000_000_000_000)
        #expect(s.cloud.cores == 0)
        #expect(s.cloud.ram == 0)
        // Owned storage is machine + cloud; cores stay the machine's alone.
        #expect(s.owned.storage == 4_500_000_000_000)
        #expect(s.owned.cores == 4)
        #expect(s.owned.ram == 16_000_000_000)
        #expect(s.cloudCount == 1)
        #expect(s.cloudMeasuredCount == 0)      // declared, not probed
    }

    @Test("Every fixed volume counts, not just the boot disk")
    func multiVolumeMachinesSumAllDisks() {
        let magi = Machine(name: "magi", kind: .remote, host: "magi", user: "hadim", os: .windows)
        let t = Self.telemetry(disks: [
            DiskVolume(name: "C:", total: 1_000_000_000_000, used: 600_000_000_000, free: 400_000_000_000),
            DiskVolume(name: "D:", total: 2_000_000_000_000, used: 300_000_000_000, free: 1_700_000_000_000),
        ])
        let s = FleetStrength.compute(machines: [magi], telemetry: [magi.id: t],
                                      capacities: [:], online: [magi.id: true], clouds: [])
        #expect(s.machines.storage == 3_000_000_000_000)
        #expect(s.machines.storageUsed == 900_000_000_000)
        #expect(s.machines.storageFree == 2_100_000_000_000)
    }

    @Test("Live telemetry wins over a stored snapshot — no double counting")
    func livePreferredOverSnapshot() {
        let mac = Machine.thisMac(name: "Mac")
        let stale = CapacitySnapshot(cores: 99, ram: 99, storage: 99, storageUsed: 99)
        let s = FleetStrength.compute(machines: [mac], telemetry: [mac.id: Self.telemetry()],
                                      capacities: [mac.id: stale], online: [mac.id: true], clouds: [])
        #expect(s.machines.cores == 4)          // the live 4, not the stored 99
        #expect(s.staleCount == 0)
    }

    @Test("A snapshot captures every volume and the honest used total")
    func snapshotFromTelemetry() {
        let t = Self.telemetry(cores: 6, ram: 8_000_000_000, disks: [
            DiskVolume(name: "/", total: 100, used: 40, free: 60),
            DiskVolume(name: "/data", total: 200, used: 10, free: 190),
        ])
        let snap = CapacitySnapshot(t)
        #expect(snap.cores == 6)
        #expect(snap.ram == 8_000_000_000)
        #expect(snap.storage == 300)
        #expect(snap.storageUsed == 50)
    }

    @Test("Containers and alerts are counted from live machines only")
    func liveOnlyCounters() {
        let a = Machine(name: "a", kind: .remote, host: "a", user: "u")
        let b = Machine(name: "b", kind: .remote, host: "b", user: "u")
        let full = Self.telemetry(disks: [DiskVolume(name: "/", total: 100, used: 95, free: 5)],
                                  containers: [Container(name: "c1", status: "Up 2 days")])
        let s = FleetStrength.compute(
            machines: [a, b],
            telemetry: [a.id: full],
            capacities: [b.id: CapacitySnapshot(cores: 1, ram: 1, storage: 1, storageUsed: 1)],
            online: [a.id: true, b.id: false],
            clouds: []
        )
        #expect(s.containers == 1)
        #expect(s.alerts == 1)                  // a's disk is at 95%
    }
}

@Suite("Cloud drive")
struct CloudDriveTests {
    @Test("Free and fraction stay nil while usage is unknown")
    func unknownUsage() {
        let d = CloudDrive(name: "Drive", provider: .googleDrive, capacity: 4_000_000_000_000)
        #expect(d.free == nil)
        #expect(d.usedFraction == nil)
        #expect(!d.isMeasured)
    }

    @Test("Usage over capacity clamps instead of going negative")
    func overfull() {
        let d = CloudDrive(name: "Drive", provider: .dropbox, capacity: 100, used: 150)
        #expect(d.free == 0)
        #expect(d.usedFraction == 1)
    }

    @Test("A measured drive is marked measured")
    func measured() {
        let d = CloudDrive(name: "Drive", provider: .oneDrive, capacity: 1_000_000_000_000,
                           used: 500_000_000_000, rcloneRemote: "onedrive:", lastMeasured: Date())
        #expect(d.isMeasured)
        #expect(d.free == 500_000_000_000)
        #expect(d.usedFraction == 0.5)
    }
}

@Suite("rclone about parser")
struct CloudProbeTests {
    @Test("Parses a full rclone about payload")
    func fullPayload() {
        let json = """
        {
            "total": 4000000000000,
            "used": 274877906944,
            "free": 3725122093056,
            "trashed": 1073741824
        }
        """
        let u = CloudProbe.parse(json)
        #expect(u?.total == 4_000_000_000_000)
        #expect(u?.used == 274_877_906_944)
        #expect(u?.free == 3_725_122_093_056)
        #expect(u?.trashed == 1_073_741_824)
    }

    @Test("Backends that report only some fields still parse")
    func partialPayload() {
        let u = CloudProbe.parse(#"{"used": 12345}"#)
        #expect(u?.used == 12345)
        #expect(u?.total == nil)
        #expect(u?.free == nil)
    }

    @Test("Junk and empty objects yield nothing rather than zeros")
    func rejectsJunk() {
        #expect(CloudProbe.parse("not json") == nil)
        #expect(CloudProbe.parse("{}") == nil)
        #expect(CloudProbe.parse(#"{"other": 1}"#) == nil)
    }
}
