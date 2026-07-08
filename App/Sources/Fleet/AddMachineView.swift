import SwiftUI
import FleetKit

/// Add a remote machine by raw Tailscale host + user. Tests the SSH
/// connection before committing, so a typo fails here, not silently later.
struct AddMachineView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = MachineStore.shared

    @State private var host = ""
    @State private var user = ""
    @State private var name = ""
    @State private var testing = false
    @State private var testResult: TestState?

    private enum TestState { case ok(String), failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a machine").font(.system(size: 17, weight: .semibold))
                Text("Connects over SSH using your existing keys — nothing is installed on the remote.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                field("Tailscale host or IP", "100.x.y.z or ssh alias", text: $host)
                field("User", "hadi", text: $user)
                field("Name (optional)", "hadi-pc", text: $name)
            }

            if let result = testResult {
                HStack(spacing: 8) {
                    switch result {
                    case .ok(let msg):
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.tierCache)
                        Text(msg).font(.system(size: 12)).foregroundStyle(.secondary)
                    case .failed(let msg):
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.tierRegenerable)
                        Text(msg).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }

            HStack {
                Button("Test connection") { Task { await test() } }
                    .buttonStyle(.bordered).disabled(host.isEmpty || user.isEmpty || testing)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Add") {
                    store.addRemote(host: host, user: user, name: name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent.opacity(0.85))
                .disabled(host.isEmpty || user.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.canvas)
    }

    private func field(_ label: String, _ placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private func test() async {
        testing = true; testResult = nil
        defer { testing = false }
        let ssh = SSHRunner(host: host, user: user)
        if await ssh.ping() {
            let os = await ssh.detectOS()
            let osName = os == .windows ? "Windows" : os == .macOS ? "macOS" : os == .linux ? "Linux" : "reachable"
            testResult = .ok("Connected — \(osName)")
        } else {
            testResult = .failed("Couldn't connect. Check the host, user, and that your SSH key works.")
        }
    }
}
