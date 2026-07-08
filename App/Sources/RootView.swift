import SwiftUI
import FleetKit

/// Local-machine organs (This Mac only — the full Stockpile depth).
enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case descend = "Descend"
    case caches = "Caches"
    case apps = "Apps"
    case heat = "Heat"
    case memory = "Memory"
    case battery = "Battery"
    case startup = "Startup"
    case ledger = "Ledger"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .descend: "square.stack.3d.down.right"
        case .caches: "arrow.3.trianglepath"
        case .apps: "square.grid.2x2"
        case .heat: "thermometer.medium"
        case .memory: "memorychip"
        case .battery: "battery.100percent"
        case .startup: "power"
        case .ledger: "book.closed"
        }
    }
}

struct RootView: View {
    @State private var store = MachineStore.shared
    /// nil = Fleet grid; otherwise the focused machine.
    @State private var focusedMachineID: UUID?
    @State private var localSection: AppSection = .overview
    @State private var remoteOrgan: RemoteOrgan = .overview
    @State private var addingMachine = false

    init() {
        _focusedMachineID = State(initialValue: MachineStore.shared.local.id)
    }

    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return "v\(v)"
    }

    private var focused: Machine? {
        focusedMachineID.flatMap { id in store.machines.first { $0.id == id } }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack {
                Backdrop()
                detail
            }
        }
        .sheet(isPresented: $addingMachine) { AddMachineView() }
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            organList
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.body).foregroundStyle(Theme.accent)
                Text("Fleetwatch").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            machinePicker
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }

    private var machinePicker: some View {
        Menu {
            Button { focusedMachineID = nil } label: { Label("Fleet", systemImage: "square.grid.3x3.fill") }
            Divider()
            ForEach(store.machines) { m in
                Button {
                    focusedMachineID = m.id
                    remoteOrgan = .overview
                } label: {
                    Label(m.name, systemImage: m.kind == .local ? "laptopcomputer" : osIcon(m.os))
                }
            }
            Divider()
            Button { addingMachine = true } label: { Label("Add machine…", systemImage: "plus") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: focused == nil ? "square.grid.3x3.fill" : (focused?.kind == .local ? "laptopcomputer" : osIcon(focused?.os ?? .unknown)))
                    .font(.system(size: 12)).foregroundStyle(Theme.accent)
                Text(focused?.name ?? "Fleet").font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var organList: some View {
        if let m = focused {
            if m.kind == .local {
                List(AppSection.allCases, selection: $localSection) { s in
                    Label(s.rawValue, systemImage: s.symbol).tag(s)
                }
                .listStyle(.sidebar)
            } else {
                List(RemoteOrgan.available(for: store.telemetry[m.id]), selection: $remoteOrgan) { o in
                    Label(o.label, systemImage: o.symbol).tag(o)
                }
                .listStyle(.sidebar)
            }
        } else {
            // Fleet focused — no organ list; the grid lives in the detail.
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Text(Self.appVersion).font(.caption2).foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.bottom, 12)
    }

    // MARK: detail

    @ViewBuilder
    private var detail: some View {
        if let m = focused {
            if m.kind == .local {
                localDetail
            } else {
                RemoteMachineView(machine: m, organ: remoteOrgan)
                    .id(m.id)   // fresh state per machine
            }
        } else {
            FleetGridView { machine in
                focusedMachineID = machine.id
                remoteOrgan = .overview
            }
        }
    }

    @ViewBuilder
    private var localDetail: some View {
        switch localSection {
        case .overview: OverviewView { localSection = $0 }
        case .descend: DescendView()
        case .caches: CachesView()
        case .apps: AppsView()
        case .heat: HeatView()
        case .memory: MemoryView()
        case .battery: BatteryView()
        case .startup: StartupView()
        case .ledger: LedgerView()
        }
    }

    private func osIcon(_ os: Machine.OS) -> String {
        switch os { case .macOS: "laptopcomputer"; case .linux: "server.rack"; case .windows: "pc"; default: "desktopcomputer" }
    }
}
