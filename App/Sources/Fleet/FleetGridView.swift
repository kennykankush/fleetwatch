import SwiftUI
import FleetKit

/// The cockpit home — every machine as an at-a-glance health tile.
struct FleetGridView: View {
    @State private var store = MachineStore.shared
    let onOpen: (Machine) -> Void
    @State private var addingMachine = false

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)]

    var body: some View {
        Screen(
            title: "Fleet",
            subtitle: "\(store.machines.count) machine\(store.machines.count == 1 ? "" : "s")",
            actions: {
                BarButton(label: "Refresh all", symbol: "arrow.clockwise") { Task { await store.refreshAll() } }
            }
        ) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.machines) { machine in
                        Button { onOpen(machine) } label: {
                            MachineTile(
                                machine: machine,
                                telemetry: store.telemetry[machine.id],
                                online: store.online[machine.id],
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
                .padding(28)
            }
        }
        .task { await store.refreshAll() }
        .sheet(isPresented: $addingMachine) { AddMachineView() }
    }
}

private struct MachineTile: View {
    let machine: Machine
    let telemetry: MachineTelemetry?
    let online: Bool?
    let refreshing: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    IconTile(symbol: osSymbol, tint: statusTint, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(machine.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(machine.kind == .local ? "this machine" : machine.host)
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Spacer()
                    statusDot
                }

                if let t = telemetry, online != false {
                    HStack(spacing: 0) {
                        stat("DISK", t.diskUsedFraction.formatted(.percent.precision(.fractionLength(0))), frac(t.diskUsedFraction))
                        stat("MEM", t.memUsedFraction.formatted(.percent.precision(.fractionLength(0))), frac(t.memUsedFraction))
                        stat("LOAD", String(format: "%.1f", t.load1), frac(t.loadFraction))
                        if t.hasDocker { stat("🐳", "\(t.containers.count)", Theme.accent) }
                    }
                } else {
                    Text(refreshing ? "connecting…" : "offline")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(tint).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var osSymbol: String {
        switch machine.os { case .macOS: "laptopcomputer"; case .linux: "server.rack"; case .windows: "pc"; default: "desktopcomputer" }
    }
    private var statusTint: Color { online == false ? .secondary : Theme.accent }
    private var statusDot: some View {
        Circle().fill(online == false ? Color.secondary.opacity(0.5) : (online == true ? Theme.tierCache : Theme.tierRegenerable))
            .frame(width: 8, height: 8)
    }
}

private struct AddTile: View {
    var body: some View {
        Card {
            HStack(spacing: 10) {
                IconTile(symbol: "plus", size: 30)
                Text("Add machine").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(minHeight: 64)
        }
    }
}

private func frac(_ f: Double) -> Color {
    f > 0.9 ? Theme.tierData : f > 0.75 ? Theme.tierRegenerable : Theme.tierCache
}
