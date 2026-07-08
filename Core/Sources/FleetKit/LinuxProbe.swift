import Foundation

/// The Linux telemetry probe: one bash script run over SSH that emits
/// section-marked output, plus a parser for it. One round-trip gathers the
/// whole picture — hardware identity, disk, memory, load, docker, battery, gpu.
public enum LinuxProbe {
    /// Runs remotely via `ssh host 'bash -s'`. Every section is best-effort;
    /// missing tools degrade to NO_* markers rather than failing the probe.
    public static let script = """
    echo "===OS==="; . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME"; uname -r
    echo "===CPU==="; nproc; lscpu 2>/dev/null | grep -E "^Model name" | sed "s/Model name: *//"
    echo "===LOAD==="; cat /proc/loadavg
    echo "===MEM==="; free -b | grep -E "^Mem"
    echo "===DISK==="; df -B1 -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs --output=target,size,used,avail 2>/dev/null | tail -n +2
    echo "===UPTIME==="; awk '{print $1}' /proc/uptime
    echo "===DOCKER==="; if command -v docker >/dev/null 2>&1; then docker ps --format '{{.Names}}|{{.Status}}' 2>/dev/null || echo DOCKER_NOPERM; else echo NO_DOCKER; fi
    echo "===BATTERY==="; ls /sys/class/power_supply/ 2>/dev/null | grep -iE "^BAT" || echo NO_BATTERY
    echo "===GPU==="; lspci 2>/dev/null | grep -iE "vga|3d|display" | sed "s/.*: //" | head -1 || echo NO_GPU
    """

    public static func parse(_ output: String) -> MachineTelemetry? {
        let sections = splitSections(output)
        guard let mem = sections["MEM"]?.first,
              let diskLines = sections["DISK"], !diskLines.isEmpty,
              let cpuLines = sections["CPU"], cpuLines.count >= 1 else { return nil }

        // MEM: "Mem:  total used free shared buff/cache available"
        let memF = mem.split(separator: " ", omittingEmptySubsequences: true).compactMap { Int64($0) }
        guard memF.count >= 6 else { return nil }
        let (memTotal, memUsed, memCached, memAvail) = (memF[0], memF[1], memF[4], memF[5])

        // DISK: one line per mount — "target size used avail". Boot/efi
        // partitions are noise; system root sorts first, then by size.
        var disks: [DiskVolume] = diskLines.compactMap { line in
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 4, let total = Int64(f[1]), let used = Int64(f[2]), let free = Int64(f[3]) else { return nil }
            let mount = String(f[0])
            guard !mount.hasPrefix("/boot") else { return nil }
            return DiskVolume(name: mount, total: total, used: used, free: free)
        }
        disks.sort { a, b in
            if a.name == "/" { return true }
            if b.name == "/" { return false }
            return a.total > b.total
        }
        guard !disks.isEmpty else { return nil }

        let cores = Int(cpuLines[0].trimmingCharacters(in: .whitespaces)) ?? 0
        let cpuModel = cpuLines.count >= 2 ? cpuLines[1] : "Unknown CPU"

        let load = (sections["LOAD"]?.first ?? "").split(separator: " ").compactMap { Double($0) }
        let uptime = TimeInterval(sections["UPTIME"]?.first ?? "") ?? 0

        let osLines = sections["OS"] ?? []
        let hardware = HardwareInfo(
            cpuModel: cpuModel, cores: cores, ramTotal: memTotal,
            gpu: sections["GPU"]?.first.flatMap { $0 == "NO_GPU" ? nil : $0 },
            osName: osLines.first ?? "Linux",
            kernel: osLines.count >= 2 ? osLines[1] : ""
        )

        let dockerLines = sections["DOCKER"] ?? ["NO_DOCKER"]
        let hasDocker = !(dockerLines.first == "NO_DOCKER")
        let containers: [Container] = hasDocker
            ? dockerLines.filter { $0.contains("|") }.map {
                let parts = $0.split(separator: "|", maxSplits: 1).map(String.init)
                return Container(name: parts[0], status: parts.count > 1 ? parts[1] : "")
              }
            : []

        let hasBattery = !((sections["BATTERY"]?.first ?? "NO_BATTERY") == "NO_BATTERY")

        return MachineTelemetry(
            hardware: hardware,
            disks: disks,
            memTotal: memTotal, memUsed: memUsed, memAvailable: memAvail, memCached: memCached,
            load1: load.count > 0 ? load[0] : 0, load5: load.count > 1 ? load[1] : 0, load15: load.count > 2 ? load[2] : 0,
            uptime: uptime, hasDocker: hasDocker, hasBattery: hasBattery, containers: containers
        )
    }

    /// Splits `===NAME===`-marked output into section → trimmed non-empty lines.
    private static func splitSections(_ output: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var current: String?
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("===") && line.hasSuffix("===") {
                current = String(line.dropFirst(3).dropLast(3))
                result[current!] = []
            } else if let current, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                result[current]?.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        return result
    }
}
