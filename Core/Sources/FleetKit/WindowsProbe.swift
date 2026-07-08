import Foundation

/// The Windows telemetry probe: a PowerShell script piped over SSH (Windows
/// OpenSSH defaults to cmd, so we pipe to `powershell -Command -`). Emits the
/// same `===SECTION===` format as the Linux probe so parsing is uniform.
public enum WindowsProbe {
    public static let script = """
    $os=Get-CimInstance Win32_OperatingSystem
    $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
    $cs=Get-CimInstance Win32_ComputerSystem
    $d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    "===OS==="; $os.Caption; [System.Environment]::OSVersion.Version.ToString()
    "===CPU==="; $cpu.NumberOfLogicalProcessors; $cpu.Name
    "===MEM==="; "$($os.TotalVisibleMemorySize) $($os.FreePhysicalMemory)"
    "===DISK==="; "$($d.Size) $($d.FreeSpace)"
    "===LOAD==="; $cpu.LoadPercentage
    "===UPTIME==="; [int]((Get-Date)-$os.LastBootUpTime).TotalSeconds
    "===GPU==="; (Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 } | Sort-Object AdapterRAM -Descending | Select-Object -First 1).Name
    "===DOCKER==="; if (Get-Command docker -ErrorAction SilentlyContinue) { docker ps --format '{{.Names}}|{{.Status}}' } else { "NO_DOCKER" }
    """

    public static func parse(_ output: String) -> MachineTelemetry? {
        let s = splitSections(output)
        guard let mem = s["MEM"]?.first, let disk = s["DISK"]?.first,
              let cpuLines = s["CPU"], cpuLines.count >= 1 else { return nil }

        // MEM: "totalVisibleKB freePhysicalKB" (KiB). Windows has no clean
        // cache figure — available ≈ free, cache unknown.
        let memF = mem.split(separator: " ").compactMap { Int64($0) }
        guard memF.count >= 2 else { return nil }
        let memTotal = memF[0] * 1024, memFree = memF[1] * 1024
        let memUsed = max(0, memTotal - memFree)

        // DISK: "size free" (bytes) for C:.
        let diskF = disk.split(separator: " ").compactMap { Int64($0) }
        guard diskF.count >= 2 else { return nil }
        let dTotal = diskF[0], dFree = diskF[1], dUsed = max(0, diskF[0] - diskF[1])

        let cores = Int(cpuLines[0].trimmingCharacters(in: .whitespaces)) ?? 0
        let cpuModel = (cpuLines.count >= 2 ? cpuLines[1] : "Unknown CPU").trimmingCharacters(in: .whitespaces)
        // Windows exposes a single CPU load %, not a load average — normalize
        // to a load-like number (fraction of cores) so the UI reads uniformly.
        let loadPct = Double(s["LOAD"]?.first ?? "0") ?? 0
        let load = loadPct / 100.0 * Double(cores)

        let osLines = s["OS"] ?? []
        let hardware = HardwareInfo(
            cpuModel: cpuModel, cores: cores, ramTotal: memTotal,
            gpu: s["GPU"]?.first.flatMap { $0.isEmpty ? nil : $0 },
            osName: osLines.first ?? "Windows",
            kernel: osLines.count >= 2 ? osLines[1] : ""
        )

        let dockerLines = s["DOCKER"] ?? ["NO_DOCKER"]
        let hasDocker = !(dockerLines.first == "NO_DOCKER")
        let containers: [Container] = hasDocker
            ? dockerLines.filter { $0.contains("|") }.map {
                let p = $0.split(separator: "|", maxSplits: 1).map(String.init)
                return Container(name: p[0], status: p.count > 1 ? p[1] : "")
              } : []

        return MachineTelemetry(
            hardware: hardware,
            diskTotal: dTotal, diskUsed: dUsed, diskFree: dFree,
            memTotal: memTotal, memUsed: memUsed, memAvailable: memFree, memCached: 0,
            load1: load, load5: load, load15: load,
            uptime: TimeInterval(s["UPTIME"]?.first ?? "") ?? 0,
            hasDocker: hasDocker, hasBattery: false, containers: containers
        )
    }

    private static func splitSections(_ output: String) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var current: String?
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
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
