import SwiftUI
import FleetKit
import ScannerKit
import MemoryKit
import BatteryKit
import ThermalKit
import LedgerKit

/// Tracks once-per-launch work (snapshots, exports).
@MainActor
enum AppRuntime {
    static var snapshotsRecorded = false
}

/// THE machine view: one bento dashboard per machine — identity strip on
/// top, then gauge cards. Local and remote machines share this; cards
/// appear based on what the machine has (multi-disk, docker, battery) and
/// the local Mac gets its extras (heat contributors, reclaimable, deltas).
struct MachineDashboard: View {
    let machine: Machine
    var onOpenCaches: () -> Void = {}
    @State private var store = MachineStore.shared
    @State private var reclaimable = ReclaimableModel.shared
    @State private var battery: BatteryReading?
    @State private var thermal: ThermalLevel?
    @State private var contributors: [HeatContributor] = []
    @State private var loadingContributors = false
    @State private var deltaBytes: Int64?
    @State private var reportCopied = false

    private var isLocal: Bool { machine.kind == .local }
    private var t: MachineTelemetry? { store.telemetry[machine.id] }
    private var online: Bool { store.online[machine.id] ?? isLocal }

    private let grid = [GridItem(.adaptive(minimum: 330, maximum: 560), spacing: 16, alignment: .top)]

    var body: some View {
        Screen(title: machine.name, subtitle: subtitle, actions: {
            if isLocal {
                BarButton(label: reportCopied ? "Copied ✓" : "Copy Report", symbol: "doc.on.doc") {
                    Task {
                        SystemReport.copyToClipboard(await SystemReport.build(reclaimable: reclaimable.grandTotal))
                        reportCopied = true
                        try? await Task.sleep(for: .seconds(2))
                        reportCopied = false
                    }
                }
            }
            BarButton(label: "Refresh", symbol: "arrow.clockwise", disabled: store.refreshing.contains(machine.id)) {
                Task { await refresh() }
            }
        }) {
            if let t {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLocal { SetupCard() }
                        identityStrip(t)
                        LazyVGrid(columns: grid, spacing: 16) {
                            StorageCard(t: t, deltaBytes: deltaBytes)
                            MemoryCard(t: t)
                            CPUCard(t: t, thermal: isLocal ? thermal : nil,
                                    contributors: contributors, loading: loadingContributors,
                                    onQuit: quit)
                            if t.hasDocker { DockerCard(containers: t.containers) }
                            if isLocal, let battery { BatteryCard(b: battery) }
                            if isLocal { ReclaimableCard(model: reclaimable, onOpen: onOpenCaches) }
                        }
                    }
                    .padding(Theme.pagePadding)
                }
            } else if store.refreshing.contains(machine.id) {
                center { ProgressView(); Text("Connecting to \(machine.host)…").font(.callout).foregroundStyle(.secondary) }
            } else {
                center {
                    Image(systemName: "wifi.slash").font(.system(size: 38, weight: .light)).foregroundStyle(Theme.inkTertiary)
                    Text("Offline").font(.system(size: 17, weight: .bold))
                    Text(store.lastError[machine.id] ?? "Couldn't reach \(machine.user)@\(machine.host).")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                    Button("Retry") { Task { await refresh() } }.buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .task(id: machine.id) { await load() }
    }

    private var subtitle: String {
        guard let t else { return isLocal ? "this machine" : (online ? machine.host : "offline · \(machine.host)") }
        let up = uptimeText(t.uptime)
        return isLocal ? "\(t.hardware.osName) · \(up)" : "\(t.hardware.osName) · \(machine.user)@\(machine.host) · \(up)"
    }

    // MARK: identity

    private func identityStrip(_ t: MachineTelemetry) -> some View {
        Card(padding: 14) {
            HStack(spacing: 10) {
                IconTile(symbol: isLocal ? "laptopcomputer" : (machine.os == .windows ? "pc" : "server.rack"),
                         tint: online ? Theme.accent : Theme.inkTertiary, size: 34)
                chip("CPU", "\(t.hardware.cpuModel.prefix(28))\(t.hardware.cpuModel.count > 28 ? "…" : "") · \(t.hardware.cores)c")
                chip("RAM", t.hardware.ramTotal.bytesFormatted)
                if let gpu = t.hardware.gpu { chip("GPU", String(gpu.prefix(24))) }
                chip("OS", t.hardware.osName)
                Spacer()
                Circle().fill(online ? Theme.ok : Theme.inkTertiary.opacity(0.5)).frame(width: 9, height: 9)
            }
        }
    }

    private func chip(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.inkTertiary)
            Text(v).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: data

    private func load() async {
        if isLocal {
            battery = BatteryMonitor().read()
            thermal = ThermalLevel(ProcessInfo.processInfo.thermalState)
            Task { await reclaimable.loadIfNeeded() }
            Task { await loadContributors() }
            if t == nil { await store.refresh(machine) }
            await recordSnapshotsOnce()
            if let prev = await LedgerStore.shared.latestSnapshot()?.metrics?["physicalUsed"],
               let now = t?.diskUsed ?? (try? DiskAccounting.measure())?.physicalUsed {
                deltaBytes = now - prev
            }
        } else if t == nil {
            await store.refresh(machine)
        }
    }

    private func refresh() async {
        await store.refresh(machine)
        if isLocal {
            battery = BatteryMonitor().read()
            thermal = ThermalLevel(ProcessInfo.processInfo.thermalState)
            await loadContributors()
        }
    }

    private func loadContributors() async {
        guard isLocal, !loadingContributors else { return }
        loadingContributors = true
        let raw = await ThermalMonitor().sample()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        contributors = raw.processes
            .filter { $0.pid != ownPID && !$0.command.localizedCaseInsensitiveContains("Fleetwatch") }
            .prefix(5)
            .map { HeatContributor(load: $0, runningApp: NSRunningApplication(processIdentifier: $0.pid)) }
        loadingContributors = false
    }

    private func quit(_ c: HeatContributor) {
        guard let app = c.runningApp else { return }
        Task {
            if await RunningApps.quitAndWait(app) {
                await LedgerStore.shared.append(LedgerEvent(
                    kind: .cleared, title: "Quit \(c.displayName)",
                    detail: "Was \(Int(c.load.cpuPercent))% CPU."))
                await loadContributors()
            }
        }
    }

    private func recordSnapshotsOnce() async {
        guard !AppRuntime.snapshotsRecorded else { return }
        AppRuntime.snapshotsRecorded = true
        if let d = try? DiskAccounting.measure() {
            await LedgerStore.shared.append(LedgerEvent(
                kind: .snapshot, title: "Disk snapshot",
                detail: "\(d.physicalUsed.bytesFormatted) physical · \(d.purgeable.bytesFormatted) purgeable",
                bytes: d.physicalUsed,
                metrics: ["physicalUsed": d.physicalUsed, "effectiveUsed": d.effectiveUsed, "purgeable": d.purgeable]))
            WidgetBridge.export(accounting: d, reclaimable: reclaimable.grandTotal)
        }
        if let m = MemoryMonitor().read() {
            await LedgerStore.shared.append(LedgerEvent(
                kind: .snapshot, title: "Memory snapshot",
                detail: "\(m.used.bytesFormatted) in use · \(m.available.bytesFormatted) available",
                bytes: m.used,
                metrics: ["memUsed": m.used, "memAvailable": m.available, "memCached": m.cached]))
        }
    }

    @ViewBuilder
    private func center(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 10) { content() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A process contributor with its owning app resolved (for quit).
struct HeatContributor: Identifiable {
    var id: Int32 { load.pid }
    let load: ProcessLoad
    let runningApp: NSRunningApplication?
    var displayName: String { runningApp?.localizedName ?? load.command }
    var isQuittable: Bool { runningApp != nil }
}

// MARK: - Cards

/// Storage: gauge for the system volume + a row per additional volume —
/// magi's D: finally shows up.
private struct StorageCard: View {
    let t: MachineTelemetry
    var deltaBytes: Int64?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Storage", symbol: "internaldrive", tint: Theme.metricDisk,
                           trailing: deltaBytes.map { AnyView(DeltaChip(bytes: $0)) })
                HStack(spacing: 20) {
                    ZStack {
                        ArcGauge(fraction: t.diskUsedFraction, tint: Theme.metricDisk, lineWidth: 12, size: 116)
                        VStack(spacing: 0) {
                            Text(t.diskUsedFraction, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-1).monospacedDigit()
                            Text(t.disks.first?.name ?? "—").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(t.disks) { d in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(d.name).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                    Spacer()
                                    Text("\(d.free.bytesFormatted) free of \(d.total.bytesFormatted)")
                                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                ProgressBar(fraction: d.usedFraction, tint: Theme.severity(d.usedFraction))
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Memory: gauge + the honest stack (in use / cached / available).
private struct MemoryCard: View {
    let t: MachineTelemetry

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Memory", symbol: "memorychip", tint: Theme.metricMemory)
                HStack(spacing: 20) {
                    ZStack {
                        ArcGauge(fraction: t.memUsedFraction, tint: Theme.metricMemory, lineWidth: 12, size: 116)
                        VStack(spacing: 0) {
                            Text(t.memUsedFraction, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-1).monospacedDigit()
                            Text("in use").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        statRow("In use", t.memUsed.bytesFormatted, Theme.metricMemory)
                        Divider().overlay(Theme.hairline)
                        statRow("Cached — reclaimable", t.memCached.bytesFormatted, Theme.purgeable)
                        Divider().overlay(Theme.hairline)
                        statRow("Available", t.memAvailable.bytesFormatted, Theme.ok)
                    }
                }
            }
        }
    }
}

/// CPU: load vs cores; local adds thermal headline + top processes w/ quit.
private struct CPUCard: View {
    let t: MachineTelemetry
    var thermal: ThermalLevel?
    var contributors: [HeatContributor] = []
    var loading = false
    var onQuit: (HeatContributor) -> Void = { _ in }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("CPU", symbol: "cpu", tint: Theme.metricCPU,
                           trailing: thermal.map { th in AnyView(TierBadge(label: th.headline, color: thermalColor(th))) })
                HStack(spacing: 20) {
                    ZStack {
                        ArcGauge(fraction: min(t.loadFraction, 1), tint: Theme.metricCPU, lineWidth: 12, size: 116)
                        VStack(spacing: 0) {
                            Text(String(format: "%.2f", t.load1))
                                .font(.system(size: 24, weight: .bold, design: .rounded)).tracking(-1).monospacedDigit()
                            Text("load · \(t.hardware.cores)c").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        statRow("1 min", String(format: "%.2f", t.load1), Theme.metricCPU)
                        Divider().overlay(Theme.hairline)
                        statRow("5 min", String(format: "%.2f", t.load5), Theme.metricCPU.opacity(0.7))
                        Divider().overlay(Theme.hairline)
                        statRow("15 min", String(format: "%.2f", t.load15), Theme.inkTertiary)
                    }
                }
                if !contributors.isEmpty {
                    Divider().overlay(Theme.hairline)
                    VStack(spacing: 2) {
                        ForEach(contributors) { c in
                            HStack(spacing: 8) {
                                if let icon = c.runningApp?.icon {
                                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "gearshape.2").font(.system(size: 10)).foregroundStyle(Theme.inkTertiary).frame(width: 16)
                                }
                                Text(c.displayName).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text("\(Int(c.load.cpuPercent))%")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
                                Button { onQuit(c) } label: {
                                    Image(systemName: "xmark.circle").font(.system(size: 10.5))
                                        .foregroundStyle(c.isQuittable ? Theme.inkTertiary : Theme.inkTertiary.opacity(0.3))
                                }
                                .buttonStyle(Pressable()).disabled(!c.isQuittable)
                                .help(c.isQuittable ? "Quit \(c.displayName)" : "System process")
                            }
                            .padding(.vertical, 3)
                        }
                    }
                } else if loading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Sampling processes…").font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
        }
    }

    private func thermalColor(_ l: ThermalLevel) -> Color {
        switch l { case .nominal: Theme.ok; case .fair: Theme.metricCPU; case .serious: Theme.metricHeat; case .critical: Theme.danger }
    }
}

/// Docker: container list with health dots.
private struct DockerCard: View {
    let containers: [Container]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("Docker", symbol: "shippingbox.fill", tint: Theme.accent,
                           trailing: AnyView(Text("\(containers.filter(\.isHealthy).count)/\(containers.count) healthy")
                               .font(.system(size: 11)).foregroundStyle(.secondary)))
                VStack(spacing: 0) {
                    ForEach(Array(containers.enumerated()), id: \.element.id) { i, c in
                        HStack(spacing: 9) {
                            Circle().fill(c.isHealthy ? Theme.ok : Theme.metricHeat).frame(width: 7, height: 7)
                            Text(c.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                            Spacer()
                            Text(c.status).font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary).lineLimit(1)
                        }
                        .padding(.vertical, 5)
                        if i < containers.count - 1 { Divider().overlay(Theme.hairline) }
                    }
                }
            }
        }
    }
}

/// Battery (local): health hero + charge/cycles.
private struct BatteryCard: View {
    let b: BatteryReading

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Battery", symbol: "battery.100percent", tint: Theme.ok,
                           trailing: AnyView(TierBadge(label: b.healthHeadline, color: healthColor)))
                HStack(spacing: 20) {
                    ZStack {
                        ArcGauge(fraction: Double(b.healthPercent) / 100, tint: healthColor, lineWidth: 12, size: 116)
                        VStack(spacing: 0) {
                            Text("\(b.healthPercent)%")
                                .font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-1).monospacedDigit()
                            Text("health").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        statRow("Charge", "\(b.charge)%", Theme.ok)
                        Divider().overlay(Theme.hairline)
                        statRow("Cycles", "\(b.cycleCount)", Theme.metricCPU)
                        Divider().overlay(Theme.hairline)
                        statRow("Capacity", "\(b.maxCapacity)/\(b.designCapacity) mAh", Theme.inkTertiary)
                    }
                }
            }
        }
    }

    private var healthColor: Color {
        switch b.healthPercent { case 90...: Theme.ok; case 80..<90: Theme.metricCPU; case 70..<80: Theme.metricHeat; default: Theme.danger }
    }
}

/// Reclaimable (local): totals + jump to Caches.
private struct ReclaimableCard: View {
    let model: ReclaimableModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    cardHeader("Reclaimable", symbol: "arrow.3.trianglepath", tint: Theme.metricHeat,
                               trailing: AnyView(Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkTertiary)))
                    if model.items.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Finding reclaimable space…").font(.system(size: 11)).foregroundStyle(Theme.inkTertiary)
                        }
                    } else {
                        Text(model.grandTotal.bytesFormatted)
                            .font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-0.8).monospacedDigit()
                        HStack(spacing: 14) {
                            LegendDot(color: Theme.ok, label: "Free to clear", detail: model.freeToClearBytes.bytesFormatted)
                            LegendDot(color: Theme.metricHeat, label: "Rebuildable", detail: model.regenerableBytes.bytesFormatted)
                        }
                    }
                }
            }
        }
        .buttonStyle(Pressable())
    }
}

// MARK: - shared bits

private func cardHeader(_ title: String, symbol: String, tint: Color, trailing: AnyView? = nil) -> some View {
    HStack(spacing: 9) {
        IconTile(symbol: symbol, tint: tint, size: 26)
        Text(title).font(.system(size: 13.5, weight: .bold))
        Spacer()
        if let trailing { trailing }
    }
}

private func statRow(_ label: String, _ value: String, _ tint: Color) -> some View {
    HStack(spacing: 8) {
        Circle().fill(tint).frame(width: 6, height: 6)
        Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.system(size: 12.5, weight: .semibold, design: .rounded)).monospacedDigit()
    }
    .padding(.vertical, 7)
}

/// Full-width slim progress bar.
struct ProgressBar: View {
    let fraction: Double
    var tint: Color = Theme.metricDisk

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(tint).frame(width: max(geo.size.width * min(fraction, 1), 3))
            }
        }
        .frame(height: 6)
    }
}

func uptimeText(_ seconds: TimeInterval) -> String {
    let days = Int(seconds) / 86400
    if days > 0 { return "up \(days)d" }
    return "up \(Int(seconds) / 3600)h"
}
