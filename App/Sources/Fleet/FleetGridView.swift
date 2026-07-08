import SwiftUI
import FleetKit

/// The cockpit home — every machine as a rich health tile with a mini gauge.
struct FleetGridView: View {
    @State private var store = MachineStore.shared
    let onOpen: (Machine) -> Void
    @State private var addingMachine = false
    @State private var updates = UpdateChecker.shared

    private let columns = [GridItem(.adaptive(minimum: 310, maximum: 460), spacing: 16, alignment: .top)]

    var body: some View {
        Screen(
            title: "Fleet",
            subtitle: "\(store.machines.count) machine\(store.machines.count == 1 ? "" : "s") · \(store.online.values.filter { $0 }.count + 1 - (store.online[store.local.id] == false ? 1 : 0)) reachable",
            actions: {
                BarButton(label: "Refresh all", symbol: "arrow.clockwise") { Task { await store.refreshAll() } }
            }
        ) {
            ScrollView {
                if let latest = updates.latestVersion {
                    UpdateBanner(version: latest)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.top, Theme.pagePadding)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.machines) { machine in
                        Button { onOpen(machine) } label: {
                            MachineTile(
                                machine: machine,
                                telemetry: store.telemetry[machine.id],
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
                    Button { addingMachine = true } label: { AddTile() }
                        .buttonStyle(Pressable())
                }
                .padding(Theme.pagePadding)
            }
        }
        .task {
            await store.refreshAll()
            await updates.checkIfNeeded()
        }
        .sheet(isPresented: $addingMachine) { AddMachineView() }
    }
}

private struct MachineTile: View {
    let machine: Machine
    let telemetry: MachineTelemetry?
    let online: Bool
    let refreshing: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    IconTile(symbol: osSymbol, tint: online ? Theme.accent : Theme.inkTertiary, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(machine.name).font(.system(size: 14.5, weight: .bold)).lineLimit(1)
                        Text(subtitleText)
                            .font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary).lineLimit(1)
                    }
                    Spacer()
                    Circle().fill(online ? Theme.ok : Theme.inkTertiary.opacity(0.4)).frame(width: 9, height: 9)
                }

                if let t = telemetry, online {
                    HStack(spacing: 16) {
                        // Mini disk gauge.
                        ZStack {
                            ArcGauge(fraction: t.diskUsedFraction, tint: Theme.metricDisk, lineWidth: 8, size: 72)
                            VStack(spacing: 0) {
                                Text(t.diskUsedFraction, format: .percent.precision(.fractionLength(0)))
                                    .font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                                Text("disk").font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 7) {
                            miniBar("MEM", t.memUsedFraction, Theme.metricMemory)
                            miniBar("LOAD", min(t.loadFraction, 1), Theme.metricCPU)
                            HStack(spacing: 10) {
                                if t.disks.count > 1 {
                                    Text("\(t.disks.count) disks")
                                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.inkTertiary)
                                }
                                if t.hasDocker {
                                    HStack(spacing: 3) {
                                        Image(systemName: "shippingbox.fill").font(.system(size: 8.5))
                                        Text("\(t.containers.count)")
                                            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                    }
                                    .foregroundStyle(Theme.accent)
                                }
                                if t.hasBattery {
                                    Image(systemName: "battery.100percent").font(.system(size: 9)).foregroundStyle(Theme.ok)
                                }
                                Spacer()
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        if refreshing { ProgressView().controlSize(.small) }
                        Text(refreshing ? "connecting…" : "offline")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.inkTertiary)
                    }
                    .frame(height: 72)
                }
            }
        }
    }

    private func miniBar(_ label: String, _ fraction: Double, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 8.5, weight: .semibold)).tracking(0.6)
                .foregroundStyle(Theme.inkTertiary).frame(width: 30, alignment: .leading)
            ProgressBar(fraction: fraction, tint: tint)
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
        }
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
    var body: some View {
        Card {
            HStack(spacing: 10) {
                IconTile(symbol: "plus", size: 32)
                Text("Add machine").font(.system(size: 13.5, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(minHeight: 100)
        }
    }
}
