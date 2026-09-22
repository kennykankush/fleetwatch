import SwiftUI
import FleetKit

/// Declare a cloud drive so its capacity counts toward the fleet.
///
/// Two ways in. If you have `rclone` remotes configured, pick one and the
/// provider answers for itself — name, backend, capacity and usage all
/// arrive from `rclone about`, and nothing is typed. Otherwise you state the
/// plan size yourself, because the sync clients mount through File Provider
/// and the OS reports your local disk rather than the plan.
struct AddCloudView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = CloudStore.shared

    /// The drive being edited, or `nil` when adding a new one.
    var editing: CloudDrive?

    @State private var name = ""
    @State private var provider: CloudDrive.Provider = .googleDrive
    @State private var amount = ""
    @State private var unit: Unit = .tb
    @State private var remote = ""              // rclone remote name, "" = none
    @State private var backend: String?
    @State private var measuredUsed: Int64?
    @State private var probing = false
    @State private var probeError: String?

    private enum Unit: String, CaseIterable, Identifiable {
        case gb = "GB", tb = "TB"
        var id: String { rawValue }
        var multiplier: Int64 { self == .tb ? 1_000_000_000_000 : 1_000_000_000 }
    }

    private var capacityBytes: Int64 {
        Int64((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * Double(unit.multiplier))
    }

    private var isValid: Bool { !name.isEmpty && capacityBytes > 0 }
    private var isLinked: Bool { !remote.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editing == nil ? "Add cloud storage" : "Edit cloud storage")
                    .font(.system(size: 17, weight: .semibold))
                Text("Counts toward the fleet's total capacity.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            if store.rcloneAvailable && !store.availableRemotes.isEmpty {
                remoteSection
                Divider().overlay(Theme.hairline)
            } else {
                rcloneHint
            }

            VStack(alignment: .leading, spacing: 10) {
                if !isLinked {
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
                }

                field("Name", "Google Drive — personal", text: $name)

                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel(isLinked ? "Plan capacity — reported by the provider" : "Plan capacity")
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
        .frame(width: 470)
        .background(Theme.canvas)
        .task {
            if let d = editing { load(d) }
            if store.rcloneAvailable { await store.loadAvailableRemotes() }
        }
    }

    // MARK: rclone

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Read from an rclone remote")
            Picker("", selection: $remote) {
                Text("Don't link — I'll enter it myself").tag("")
                ForEach(store.availableRemotes) { r in
                    Text("\(r.name)  ·  \(r.description)").tag(r.name)
                }
            }
            .labelsHidden().pickerStyle(.menu)
            .onChange(of: remote) { _, new in
                Task { await link(new) }
            }

            if probing {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Asking \(remote) for its quota…")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else if let probeError {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.metricHeat)
                    Text(probeError).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if isLinked, let used = measuredUsed {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.ok)
                    Text("\(backend ?? provider.displayName) reports \(capacityBytes.bytesFormatted) · \(used.bytesFormatted) used")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Text("rclone holds the credentials — Fleetwatch never sees them.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary)
            }
        }
    }

    private var rcloneHint: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Theme.inkTertiary)
            Text(store.rcloneAvailable
                 ? "No rclone remotes configured yet. Run `rclone config` to link an account and the capacity fills itself in."
                 : "Install rclone and link an account to read capacity and usage automatically. Without it, declare the plan below — it still counts.")
                .font(.system(size: 11)).foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Picking a remote fills in everything it can: the backend's own label,
    /// a matching provider, and the real capacity/usage from `rclone about`.
    private func link(_ remoteName: String) async {
        probeError = nil
        guard !remoteName.isEmpty else { backend = nil; measuredUsed = nil; return }
        guard let r = store.availableRemotes.first(where: { $0.name == remoteName }) else { return }

        provider = CloudDrive.Provider.from(rcloneType: r.type)
        backend = r.description
        if name.isEmpty || CloudDrive.Provider.allCases.contains(where: { $0.displayName == name }) {
            name = r.description
        }

        guard provider.canReportUsage else {
            probeError = "\(r.description) doesn't report usage — enter the capacity yourself."
            return
        }

        probing = true
        defer { probing = false }
        switch await store.inspect(r) {
        case .success(let usage):
            if let total = usage.total, total > 0 { setCapacity(total) }
            measuredUsed = usage.used
            if usage.total == nil {
                probeError = "\(r.description) reported usage but not a plan size — enter the capacity yourself."
            }
        case .failure(let error):
            probeError = error.localizedDescription
        }
    }

    private func setCapacity(_ bytes: Int64) {
        if bytes >= Unit.tb.multiplier {
            unit = .tb
            amount = trimmed(Double(bytes) / Double(Unit.tb.multiplier))
        } else {
            unit = .gb
            amount = trimmed(Double(bytes) / Double(Unit.gb.multiplier))
        }
    }

    // MARK: load / save

    private func load(_ d: CloudDrive) {
        name = d.name
        provider = d.provider
        remote = (d.rcloneRemote ?? "").replacingOccurrences(of: ":", with: "")
        backend = d.backend
        measuredUsed = d.used
        setCapacity(d.capacity)
    }

    /// "4" not "4.0"; "1.5" stays "1.5".
    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
    }

    private func commit() {
        let linkedRemote = remote.isEmpty ? nil : remote
        if var d = editing {
            d.name = name
            d.provider = provider
            d.capacity = capacityBytes
            d.rcloneRemote = linkedRemote
            d.backend = backend
            if let measuredUsed { d.used = measuredUsed; d.lastMeasured = Date() }
            store.update(d)
        } else {
            store.add(CloudDrive(name: name, provider: provider,
                                 capacity: capacityBytes,
                                 used: measuredUsed,
                                 rcloneRemote: linkedRemote,
                                 backend: backend,
                                 lastMeasured: measuredUsed == nil ? nil : Date()))
        }
        dismiss()
    }

    // MARK: chrome

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
