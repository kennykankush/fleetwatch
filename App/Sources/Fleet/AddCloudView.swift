import SwiftUI
import FleetKit

/// Declare a cloud drive so its capacity counts toward the fleet.
///
/// Capacity is typed in, not discovered: the sync clients mount through File
/// Provider, so the OS reports the local disk rather than the plan. If
/// `rclone` is configured, pointing this at a remote lets the provider answer
/// for itself instead.
struct AddCloudView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = CloudStore.shared

    /// The drive being edited, or `nil` when adding a new one.
    var editing: CloudDrive?

    @State private var name = ""
    @State private var provider: CloudDrive.Provider = .googleDrive
    @State private var amount = ""
    @State private var unit: Unit = .tb
    @State private var remote = ""

    private enum Unit: String, CaseIterable, Identifiable {
        case gb = "GB", tb = "TB"
        var id: String { rawValue }
        var multiplier: Int64 { self == .tb ? 1_000_000_000_000 : 1_000_000_000 }
    }

    private var capacityBytes: Int64 {
        Int64((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * Double(unit.multiplier))
    }

    private var isValid: Bool { !name.isEmpty && capacityBytes > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editing == nil ? "Add cloud storage" : "Edit cloud storage")
                    .font(.system(size: 17, weight: .semibold))
                Text("Counts toward the fleet's total capacity. No sign-in — the plan size is yours to state.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Provider")
                    Picker("", selection: $provider) {
                        ForEach(CloudDrive.Provider.allCases) { p in
                            Label(p.displayName, systemImage: p.symbol).tag(p)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .onChange(of: provider) { _, new in
                        if name.isEmpty || CloudDrive.Provider.allCases.contains(where: { $0.displayName == name }) {
                            name = new.displayName
                        }
                    }
                }

                field("Name", "Google Drive — personal", text: $name)

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Plan capacity")
                    HStack(spacing: 8) {
                        TextField("4", text: $amount)
                            .textFieldStyle(.plain).font(.system(size: 13)).monospacedDigit()
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                        Picker("", selection: $unit) {
                            ForEach(Unit.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 96)
                    }
                    if capacityBytes > 0 {
                        Text(capacityBytes.bytesFormatted)
                            .font(.system(size: 11)).foregroundStyle(Theme.inkTertiary).monospacedDigit()
                    }
                }

                if store.rcloneAvailable {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Live usage via rclone (optional)")
                        Picker("", selection: $remote) {
                            Text("Don't measure").tag("")
                            ForEach(store.availableRemotes, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu)
                        Text("Fleetwatch reads your existing rclone config. It never stores a cloud credential.")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Theme.inkTertiary)
                        Text("Install rclone to read live usage. Without it, capacity still counts.")
                            .font(.system(size: 11)).foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button(editing == nil ? "Add" : "Save") { commit() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent.opacity(0.85))
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.canvas)
        .task {
            if let d = editing { load(d) }
            if store.rcloneAvailable { await store.loadAvailableRemotes() }
        }
    }

    private func load(_ d: CloudDrive) {
        name = d.name
        provider = d.provider
        remote = d.rcloneRemote ?? ""
        if d.capacity >= Unit.tb.multiplier {
            unit = .tb
            amount = trimmed(Double(d.capacity) / Double(Unit.tb.multiplier))
        } else {
            unit = .gb
            amount = trimmed(Double(d.capacity) / Double(Unit.gb.multiplier))
        }
    }

    /// "4" not "4.0"; "1.5" stays "1.5".
    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    private func commit() {
        if var d = editing {
            d.name = name
            d.provider = provider
            d.capacity = capacityBytes
            d.rcloneRemote = remote.isEmpty ? nil : remote
            store.update(d)
            if !remote.isEmpty { Task { await store.refresh(d) } }
        } else {
            store.add(CloudDrive(name: name, provider: provider,
                                 capacity: capacityBytes,
                                 rcloneRemote: remote.isEmpty ? nil : remote))
        }
        dismiss()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
    }

    private func field(_ label: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(label)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}
