import SwiftUI
import FleetKit

/// The cockpit home — the fleet's total strength over an instrument-cluster
/// tile per machine, then the cloud drives that carry the rest of it.
struct FleetGridView: View {
    @State private var store = MachineStore.shared
    @State private var clouds = CloudStore.shared
    let onOpen: (Machine) -> Void
    @State private var addingMachine = false
    @State private var addingCloud = false
    @State private var editingCloud: CloudDrive?
    @State private var updates = UpdateChecker.shared

    private let columns = [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 16, alignment: .top)]

    private var strength: FleetStrength { store.strength(clouds: clouds.drives) }

    var body: some View {
        Screen(
            title: "Fleet",
            subtitle: subtitle,
            actions: {
                BarButton(label: "Refresh all", symbol: "arrow.clockwise") {
                    Task {
                        async let m: Void = store.refreshAll()
                        async let c: Void = clouds.refreshAll()
                        _ = await (m, c)
                    }
                }
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let latest = updates.latestVersion {
                        UpdateBanner(version: latest)
                    }

                    StrengthBand(s: strength)

                    SectionLabel(text: "Machines",
                                 trailing: "\(strength.reachableCount)/\(strength.machineCount) reachable")
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.machines) { machine in
                            Button { onOpen(machine) } label: {
                                MachineTile(
                                    machine: machine,
                                    telemetry: store.telemetry[machine.id],
                                    capacity: store.capacities[machine.id],
                                    online: store.online[machine.id] ?? (machine.kind == .local),
                                    refreshing: store.refreshing.contains(machine.id)
                                )
                            }
                            .buttonStyle(Pressable())
                            .contextMenu {
                                if machine.kind == .remote {
                                    Button("Remove", role: .destructive) { store.remove(machine) }
                                }
                            }
                        }
                        Button { addingMachine = true } label: {
                            AddTile(symbol: "plus", title: "Add machine",
                                    caption: "Connect over Tailscale SSH")
                        }
                        .buttonStyle(Pressable())
                    }

                    SectionLabel(text: "Cloud", trailing: cloudTrailing)
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(clouds.drives) { drive in
                            Button { editingCloud = drive } label: {
                                CloudTile(drive: drive,
                                          refreshing: clouds.refreshing.contains(drive.id),
                                          error: clouds.lastError[drive.id])
                            }
                            .buttonStyle(Pressable())
                            .contextMenu {
                                Button("Edit…") { editingCloud = drive }
                                if drive.rcloneRemote != nil {
                                    Button("Refresh usage") { Task { await clouds.refresh(drive) } }
                                }
                                Button("Remove", role: .destructive) { clouds.remove(drive) }
                            }
                        }
                        Button { addingCloud = true } label: {
                            AddTile(symbol: "cloud", title: "Add cloud storage",
                                    caption: "Declare a plan's capacity")
                        }
                        .buttonStyle(Pressable())
                    }
                }
                .padding(Theme.pagePadding)
            }
        }
        .task {
            await store.refreshAll()
            await clouds.refreshAll()
            WidgetBridge.exportFleet(store.strength(clouds: clouds.drives))
            await updates.checkIfNeeded()
        }
        .sheet(isPresented: $addingMachine) { AddMachineView() }
        .sheet(isPresented: $addingCloud) { AddCloudView() }
        .sheet(item: $editingCloud) { AddCloudView(editing: $0) }
    }

    private var subtitle: String {
        let m = "\(strength.machineCount) machine\(strength.machineCount == 1 ? "" : "s")"
        let r = "\(strength.reachableCount) reachable"
        guard strength.cloudCount > 0 else { return "\(m) · \(r)" }
        return "\(m) · \(r) · \(strength.cloudCount) cloud drive\(strength.cloudCount == 1 ? "" : "s")"
    }

    private var cloudTrailing: String {
        guard strength.cloudCount > 0 else { return "none yet" }
        return strength.cloud.storage.bytesFormatted
    }
}

// MARK: - Fleet strength

/// The mission-control hero: everything you own, in one number, with the
/// honest split underneath — how much is on machines, how much is in the
/// cloud, and how much of it answered just now.
private struct StrengthBand: View {
    let s: FleetStrength

    private let cols = [GridItem(.adaptive(minimum: 150, maximum: .infinity), spacing: 0, alignment: .leading)]

    var body: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                header
                capacity
                Divider().overlay(Theme.hairline)
                LazyVGrid(columns: cols, spacing: 4) {
                    cell("CORES", "\(s.owned.cores)", coreCaption, "cpu", Theme.metricCPU)
                    cell("MEMORY", s.owned.ram.bytesFormatted, ramCaption, "memorychip", Theme.metricMemory)
                    cell("MACHINES", "\(s.reachableCount)/\(s.machineCount)", "reachable", "wifi", Theme.accent)
                    if s.cloudCount > 0 {
                        cell("CLOUD", "\(s.cloudCount)", cloudCaption, "cloud", Theme.metricHeat)
                    }
                    if s.containers > 0 {
                        cell("CONTAINERS", "\(s.containers)", "running", "shippingbox.fill", Theme.ok)
                    }
                    if s.alerts > 0 {
                        cell("ALERTS", "\(s.alerts)", "need a look", "exclamationmark.triangle.fill", Theme.danger)
                    }
                }
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("FLEET STRENGTH")
                .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Theme.inkTertiary)
            Spacer()
            if s.hasStaleData {
                HStack(spacing: 5) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 9))
                    Text("\(s.staleCount) counted from last seen")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Theme.inkTertiary)
            }
            if s.unknownCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "questionmark.circle").font(.system(size: 9))
                    Text("\(s.unknownCount) never read")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(Theme.metricHeat)
            }
        }
    }

    // MARK: capacity

    private var capacity: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(s.owned.storage.bytesFormatted)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-1).monospacedDigit()
                Text("total capacity")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text("\(s.owned.storageUsed.bytesFormatted) used · \(s.owned.storageFree.bytesFormatted) free")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary).monospacedDigit()
            }

            CapacityBar(machines: s.machines, cloud: s.cloud)

            HStack(spacing: 14) {
                legend(Theme.metricDisk, "Machines", s.machines.storage)
                if s.cloudCount > 0 { legend(Theme.metricHeat, "Cloud", s.cloud.storage) }
                Spacer()
                Text("solid = used")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
            }
        }
    }

    private func legend(_ tint: Color, _ label: String, _ bytes: Int64) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 9, height: 9)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(bytes.bytesFormatted)
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
        }
    }

    // MARK: stat cells

    private func cell(_ label: String, _ value: String, _ caption: String,
                      _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 11) {
            IconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
                    .foregroundStyle(Theme.inkTertiary).lineLimit(1).fixedSize()
                Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).tracking(-0.4)
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).allowsTightening(true)
                Text(caption).font(.system(size: 10)).foregroundStyle(Theme.inkTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coreCaption: String {
        s.machinesReachable.cores == s.machines.cores ? "all online" : "\(s.machinesReachable.cores) online"
    }
    private var ramCaption: String {
        s.machinesReachable.ram == s.machines.ram ? "all online" : "\(s.machinesReachable.ram.bytesFormatted) online"
    }
    private var cloudCaption: String {
        s.cloudMeasuredCount == s.cloudCount ? "measured" : "\(s.cloudCount - s.cloudMeasuredCount) declared"
    }
}

/// One bar, four segments: machine used/free then cloud used/free. Solid is
/// consumed, pale is headroom — so the eye reads "how full am I, and where".
private struct CapacityBar: View {
    let machines: FleetStrength.Tally
    let cloud: FleetStrength.Tally

    var body: some View {
        GeometryReader { geo in
            let total = Double(machines.storage + cloud.storage)
            let w = geo.size.width
            HStack(spacing: 0) {
                if total > 0 {
                    segment(width: w * Double(machines.storageUsed) / total, tint: Theme.metricDisk)
                    segment(width: w * Double(machines.storageFree) / total, tint: Theme.metricDisk.opacity(0.22))
                    segment(width: w * Double(cloud.storageUsed) / total, tint: Theme.metricHeat)
                    segment(width: w * Double(cloud.storageFree) / total, tint: Theme.metricHeat.opacity(0.22))
                } else {
                    Rectangle().fill(Theme.track)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(height: 14)
    }

    private func segment(width: Double, tint: Color) -> some View {
        Rectangle().fill(tint).frame(width: max(0, width))
    }
}

/// A usage bar that fills its container. (`SizeBar` is deliberately
/// fixed-width for table rows; a card wants the whole line.)
private struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(tint)
                    .frame(width: max(geo.size.width * min(max(fraction, 0), 1), fraction > 0 ? 3 : 0))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Cloud tile

private struct CloudTile: View {
    let drive: CloudDrive
    let refreshing: Bool
    let error: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    IconTile(symbol: drive.provider.symbol, tint: drive.provider.tint, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(drive.name).font(.system(size: 15, weight: .bold)).tracking(-0.2).lineLimit(1)
                            sourcePill
                            Spacer(minLength: 0)
                        }
                        Text(drive.backendLabel)
                            .font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary).lineLimit(1)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(drive.capacity.bytesFormatted)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .tracking(-0.6).monospacedDigit()
                    Text("capacity").font(.system(size: 11)).foregroundStyle(Theme.inkTertiary)
                    Spacer()
                    if refreshing { ProgressView().controlSize(.small) }
                }

                if let fraction = drive.usedFraction, let used = drive.used {
                    VStack(alignment: .leading, spacing: 6) {
                        UsageBar(fraction: fraction, tint: drive.provider.tint)
                        HStack(spacing: 0) {
                            Text("\(used.bytesFormatted) used")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                            Spacer()
                            Text("\((drive.free ?? 0).bytesFormatted) free")
                                .font(.system(size: 11)).foregroundStyle(Theme.inkTertiary).monospacedDigit()
                        }
                    }
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkTertiary)
                        Text("Usage unknown — capacity still counts")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkTertiary)
                    }
                }

                if let error {
                    Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.metricHeat).lineLimit(2)
                } else if let measured = drive.lastMeasured {
                    Text("measured \(measured.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 172, alignment: .top)
        }
    }

    /// Says where the number came from. A typed figure never poses as a
    /// measurement.
    private var sourcePill: some View {
        let measured = drive.isMeasured
        let tint = measured ? Theme.ok : Theme.inkTertiary
        return HStack(spacing: 5) {
            Image(systemName: measured ? "dot.radiowaves.left.and.right" : "hand.raised")
                .font(.system(size: 8))
            Text(measured ? "Measured" : "Declared").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Machine tile

private struct MachineTile: View {
    let machine: Machine
    let telemetry: MachineTelemetry?
    let capacity: CapacitySnapshot?
    let online: Bool
    let refreshing: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                // Header — fixed height (icon + name/status + subtitle).
                HStack(alignment: .center, spacing: 10) {
                    IconTile(symbol: osSymbol, tint: online ? Theme.accent : Theme.inkTertiary, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(machine.name).font(.system(size: 15, weight: .bold)).tracking(-0.2).lineLimit(1)
                            statusPill
                            Spacer(minLength: 0)
                        }
                        Text(subtitleText).font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary).lineLimit(1)
                    }
                }

                if let t = telemetry, online {
                    hardwareLine(t)            // fixed 1 line
                    gauges(t)                  // fixed anchor — aligns across all cards
                    Divider().overlay(Theme.hairline)
                    footer(t)                  // two consistent bands
                } else {
                    Spacer(minLength: 0)
                    offlineBody
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 236, alignment: .top)
        }
    }

    /// An offline machine isn't a blank — it still tells you what it is and
    /// what it's holding, from the last time it answered.
    private var offlineBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if refreshing { ProgressView().controlSize(.small) }
                else { Image(systemName: "wifi.slash").font(.system(size: 13)).foregroundStyle(Theme.inkTertiary) }
                Text(refreshing ? "connecting…" : "offline")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.inkTertiary)
                Spacer()
            }
            if let c = capacity {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 9.5)).foregroundStyle(Theme.inkTertiary)
                    Text("\(c.cores) cores · \(c.ram.bytesFormatted) · \(c.storage.bytesFormatted)")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("still counted — last seen \(c.measured.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10)).foregroundStyle(Theme.inkTertiary)
            }
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text(status.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(status.color)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(status.color.opacity(0.12), in: Capsule())
    }

    // Hardware identity chip line — this is a hardware monitor first.
    private func hardwareLine(_ t: MachineTelemetry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu").font(.system(size: 9.5)).foregroundStyle(Theme.inkTertiary)
            Text(hwText(t)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // The instrument cluster: three gauges.
    private func gauges(_ t: MachineTelemetry) -> some View {
        HStack(spacing: 8) {
            gauge("DISK", t.diskUsedFraction, Theme.metricDisk)
            gauge("MEM", t.memUsedFraction, Theme.metricMemory)
            gauge("CPU", min(t.loadFraction, 1), Theme.metricCPU)
        }
        .frame(maxWidth: .infinity)
    }

    private func gauge(_ label: String, _ fraction: Double, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                ArcGauge(fraction: fraction, tint: tint, lineWidth: 7, size: 70)
                    .animation(.easeOut(duration: 0.4), value: fraction)
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 16, weight: .bold, design: .rounded)).tracking(-0.5).monospacedDigit()
            }
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.9).foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // Footer — two consistent bands so every tile has the same shape:
    //   band 1: a named chip per drive (magi's C: AND D: both show)
    //   band 2: capability chips (temp / net / gpu / docker / battery)
    private func footer(_ t: MachineTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(t.disks.prefix(3)) { d in
                    vital("internaldrive", "\(d.name) \(d.free.bytesFormatted)", Theme.metricDisk)
                }
                if t.disks.count > 3 { vital("externaldrive", "+\(t.disks.count - 3)", Theme.inkTertiary) }
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                if let temp = primaryTemp(t) {
                    vital("thermometer.medium", "\(Int(temp.celsius.rounded()))°", Theme.tempColor(temp.celsius))
                }
                if let tp = t.throughput, tp.netRx + tp.netTx > 0 {
                    vital("arrow.down.arrow.up", "\(shortRate(tp.netRx))↓ \(shortRate(tp.netTx))↑", Theme.accent)
                }
                if let g = t.gpu {
                    vital("cpu.fill", "GPU \(Int((g.utilization * 100).rounded()))%", Theme.metricGPU)
                }
                if t.hasDocker {
                    vital("shippingbox.fill", "\(t.containers.filter(\.isHealthy).count)/\(t.containers.count)", Theme.accent)
                }
                if t.hasBattery { vital("battery.100percent", nil, Theme.ok) }
                if t.swapPressured {
                    vital("exclamationmark.triangle.fill", "SWAP \(Int((t.swapUsedFraction * 100).rounded()))%",
                          Theme.severity(t.swapUsedFraction))
                }
            }
        }
    }

    /// Compact rate for a tile chip: "1.2M", "340K", "8K", "0".
    private func shortRate(_ bytesPerSec: Int64) -> String {
        let b = Double(bytesPerSec)
        if b >= 1_000_000 { return String(format: "%.1fM", b / 1_000_000) }
        if b >= 1_000 { return String(format: "%.0fK", b / 1_000) }
        return "\(bytesPerSec)"
    }

    /// The most telling temperature to headline on the tile — CPU, else GPU, else hottest.
    private func primaryTemp(_ t: MachineTelemetry) -> TempReading? {
        t.temps.first { $0.label == "CPU" } ?? t.temps.first { $0.label == "GPU" } ?? t.temps.max { $0.celsius < $1.celsius }
    }

    private func vital(_ symbol: String, _ text: String?, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9.5)).foregroundStyle(tint)
            if let text {
                Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    .monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4.5)
        .background(tint.opacity(0.09), in: Capsule())
    }

    // MARK: derived

    private var status: (label: String, color: Color) {
        guard online, let t = telemetry else { return ("Offline", Theme.inkTertiary) }
        var worst = max(t.diskUsedFraction, t.memUsedFraction, min(t.loadFraction, 1))
        if t.swapPressured { worst = max(worst, t.swapUsedFraction) }
        if worst > 0.9 { return ("Critical", Theme.danger) }
        if worst > 0.75 { return ("Warm", Theme.metricHeat) }
        return ("Healthy", Theme.ok)
    }

    private func hwText(_ t: MachineTelemetry) -> String {
        var parts: [String] = []
        if !t.hardware.cpuModel.isEmpty { parts.append(cleanCPU(t.hardware.cpuModel)) }
        parts.append("\(t.hardware.cores) cores")
        parts.append(t.hardware.ramTotal.bytesFormatted)
        if let gpu = t.hardware.gpu { parts.append(shortGPU(gpu)) }
        return parts.joined(separator: "  ·  ")
    }

    private func cleanCPU(_ s: String) -> String {
        s.replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
            .replacingOccurrences(of: " Processor", with: "")
            .replacingOccurrences(of: " CPU", with: "")
            .replacingOccurrences(of: #"\s+\d+-Core"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "AMD ", with: "")
            .replacingOccurrences(of: "Intel ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func shortGPU(_ s: String) -> String {
        s.replacingOccurrences(of: "NVIDIA GeForce ", with: "")
            .replacingOccurrences(of: "NVIDIA ", with: "")
            .replacingOccurrences(of: "AMD Radeon ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private var subtitleText: String {
        if machine.kind == .local { return "this machine" }
        if let t = telemetry, online { return "\(t.hardware.osName) · \(machine.host)" }
        return machine.host
    }

    private var osSymbol: String {
        if machine.kind == .local { return "laptopcomputer" }
        switch machine.os { case .windows: return "pc"; case .linux: return "server.rack"; default: return "desktopcomputer" }
    }
}

private struct AddTile: View {
    let symbol: String
    let title: String
    let caption: String

    var body: some View {
        Card {
            VStack(spacing: 10) {
                IconTile(symbol: symbol, size: 40)
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text(caption).font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 172)
        }
    }
}
