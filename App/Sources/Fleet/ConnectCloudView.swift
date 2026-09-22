import SwiftUI
import FleetKit

/// Connect a cloud account without leaving the app.
///
/// rclone's `--non-interactive` config protocol hands back one question at a
/// time as JSON; this renders each one and sends the answer back. The sign-in
/// itself happens on the provider's own page — rclone opens the browser and
/// keeps the token. Fleetwatch only asks the questions.
struct ConnectCloudView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = CloudStore.shared

    /// Called with the finished remote so the caller can add it as a drive.
    var onConnected: (CloudProbe.Remote) -> Void = { _ in }

    private enum Phase: Equatable {
        case choosing
        case asking(RcloneConfig.Question)
        case working(String)
        case failed(String)
        case done(String)
    }

    @State private var phase: Phase = .choosing
    @State private var providers: [RcloneConfig.Provider] = []
    @State private var backend = "onedrive"
    @State private var remoteName = ""
    @State private var answer = ""
    @State private var started = false

    private var provider: RcloneConfig.Provider? {
        providers.first { $0.name == backend }
    }
    private var providerLabel: String { provider?.description ?? backend }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider().overlay(Theme.hairline)

            Group {
                switch phase {
                case .choosing: chooser
                case .asking(let q): question(q)
                case .working(let message): working(message)
                case .failed(let message): failure(message)
                case .done(let message): success(message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 500, height: 430)
        .background(Theme.canvas)
        .task {
            providers = await RcloneConfig.providers()
            if providers.contains(where: { $0.name == "onedrive" }) == false,
               let first = providers.first { backend = first.name }
        }
    }

    // MARK: chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Connect cloud storage").font(.system(size: 17, weight: .semibold))
            Text("You sign in on \(providerLabel)'s own page. Fleetwatch never sees the password or the token.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if case .asking = phase {
                Text("rclone is asking — answers go straight to it.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
            switch phase {
            case .choosing:
                Button("Cancel") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Connect") { Task { await begin() } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent.opacity(0.85))
                    .disabled(cleanName.isEmpty)
            case .asking(let q):
                Button("Cancel") { Task { await abandon() } }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Continue") { Task { await send(q) } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent.opacity(0.85))
                    .disabled(q.required && answer.isEmpty)
            case .working:
                Button("Cancel") { Task { await abandon() } }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            case .failed:
                Button("Close") { Task { await abandon() } }.buttonStyle(.plain).foregroundStyle(.secondary)
                Button("Try again") { phase = .choosing }
                    .buttonStyle(.borderedProminent).tint(Theme.accent.opacity(0.85))
            case .done:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent.opacity(0.85))
            }
        }
    }

    // MARK: phases

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                label("Provider")
                Picker("", selection: $backend) {
                    ForEach(providers) { p in Text(p.description).tag(p.name) }
                }
                .labelsHidden().pickerStyle(.menu)
                .onChange(of: backend) { _, new in
                    if remoteName.isEmpty || providers.contains(where: { $0.name == remoteName }) {
                        remoteName = new
                    }
                }
                Text("\(providers.count) services, straight from rclone.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary)
            }
            VStack(alignment: .leading, spacing: 4) {
                label("Name it")
                TextField(backend, text: $remoteName)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                Text("How this account is labelled in rclone — letters, digits, dashes.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary)
            }
        }
    }

    @ViewBuilder
    private func question(_ q: RcloneConfig.Question) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !q.error.isEmpty {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.metricHeat)
                        Text(q.error).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                label(q.label)
                if !q.help.isEmpty {
                    Text(q.help)
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if q.isBool || (q.exclusive && !q.choices.isEmpty) {
                    // Few options read better as a segmented row; a long list
                    // (rclone's region and provider questions run to dozens)
                    // has to be a menu.
                    if q.choices.count <= 3 {
                        choicePicker(q).pickerStyle(.segmented)
                    } else {
                        choicePicker(q).pickerStyle(.menu)
                    }
                } else if q.isPassword {
                    SecureField("", text: $answer)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                } else {
                    TextField(q.defaultValue.isEmpty ? "" : q.defaultValue, text: $answer)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                    if !q.defaultValue.isEmpty {
                        Text("Leave as-is for the default: \(q.defaultValue)")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
        }
    }

    private func choicePicker(_ q: RcloneConfig.Question) -> some View {
        Picker("", selection: $answer) {
            ForEach(q.choices) { c in
                Text(c.help.isEmpty ? c.value : c.help).tag(c.value)
            }
        }
        .labelsHidden()
    }

    private func working(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(message).font(.system(size: 13, weight: .medium))
            }
            Text("If a browser window opened, finish signing in there — this waits for it.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.danger)
                Text("Couldn't connect").font(.system(size: 13, weight: .semibold))
            }
            ScrollView {
                Text(message).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
    }

    private func success(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                Text("Connected").font(.system(size: 13, weight: .semibold))
            }
            Text(message).font(.system(size: 11.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
    }

    // MARK: flow

    /// rclone remote names can't contain spaces or a colon.
    private var cleanName: String {
        remoteName.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ":", with: "")
    }

    private func begin() async {
        started = true
        phase = .working("Starting \(providerLabel)…")
        await run { try await RcloneConfig.begin(remote: cleanName, backend: backend) }
    }

    private func send(_ q: RcloneConfig.Question) async {
        let result = answer.isEmpty ? q.defaultValue : answer
        phase = .working("Talking to \(providerLabel)…")
        await run {
            try await RcloneConfig.answer(remote: cleanName, backend: backend,
                                          state: q.state, result: result)
        }
    }

    private func run(_ operation: @Sendable () async throws -> RcloneConfig.Step) async {
        do {
            switch try await operation() {
            case .ask(let next):
                // Preselect the default so Continue is always a valid answer.
                answer = next.defaultValue
                phase = .asking(next)
            case .finished:
                await finish()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// The remote exists now — read what it is, ask it how big it is, and hand
    /// it back to the caller as a drive.
    private func finish() async {
        phase = .working("Reading the account…")
        await store.loadAvailableRemotes()
        guard let remote = store.availableRemotes.first(where: { $0.name == cleanName }) else {
            phase = .failed("rclone finished but no remote called \(cleanName) appeared.")
            return
        }
        started = false
        onConnected(remote)
        switch await store.inspect(remote) {
        case .success(let usage):
            let total = usage.total.map { $0.bytesFormatted } ?? "unknown capacity"
            let used = usage.used.map { " · \($0.bytesFormatted) used" } ?? ""
            phase = .done("\(remote.description) — \(total)\(used)")
        case .failure:
            phase = .done("\(remote.description) connected. It doesn't report usage, so set the capacity yourself.")
        }
    }

    /// Backing out mid-flow leaves a stub remote behind — clean it up.
    private func abandon() async {
        if started { await RcloneConfig.cancel(remote: cleanName) }
        dismiss()
    }
}
