import Foundation

/// Runs commands on a remote machine over SSH — agentless, using the user's
/// existing keys/agent (BatchMode: never prompts, fails fast). Shell-aware so
/// it can drive both `bash -s` (Linux/macOS) and `powershell -Command -`
/// (Windows).
public struct SSHRunner: Sendable {
    public let host: String
    public let user: String
    public let connectTimeout: Int

    public init(host: String, user: String, connectTimeout: Int = 8) {
        self.host = host
        self.user = user
        self.connectTimeout = connectTimeout
    }

    public enum Shell: Sendable {
        case bash
        case powershell
        var invocation: String {
            switch self {
            case .bash: "bash -s"
            case .powershell: "powershell -NoProfile -NonInteractive -Command -"
            }
        }
    }

    public enum SSHError: Error, LocalizedError {
        case unreachable(String)
        public var errorDescription: String? {
            switch self { case .unreachable(let s): "Couldn't reach \(s)" }
        }
    }

    /// Pipes `script` to the chosen shell on the remote and returns stdout.
    public func run(_ script: String, shell: Shell = .bash) async throws -> String {
        try await exec(remote: shell.invocation, stdin: script)
    }

    /// Runs a bare command directly (no shell wrapper) — used for OS detection.
    public func runCommand(_ command: String) async throws -> String {
        try await exec(remote: command, stdin: nil)
    }

    /// Detects the remote OS cheaply: `uname -s` succeeds on Linux/macOS,
    /// fails on Windows cmd — so the output tells us which probe to run.
    public func detectOS() async -> Machine.OS {
        let out = ((try? await runCommand("uname -s")) ?? "")
        if out.contains("Linux") { return .linux }
        if out.contains("Darwin") { return .macOS }
        return .windows
    }

    public func ping() async -> Bool {
        (try? await runCommand("echo ok"))?.contains("ok") ?? false
    }

    private func exec(remote: String, stdin: String?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=\(connectTimeout)",
                "-o", "StrictHostKeyChecking=accept-new",
                "\(user)@\(host)", remote,
            ]
            let stdinPipe = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
                if let stdin { stdinPipe.fileHandleForWriting.write(Data(stdin.utf8)) }
                stdinPipe.fileHandleForWriting.closeFile()
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 && data.isEmpty {
                    continuation.resume(throwing: SSHError.unreachable("\(user)@\(host)"))
                } else {
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                }
            } catch {
                continuation.resume(throwing: SSHError.unreachable("\(user)@\(host)"))
            }
        }
    }
}

/// Reads a machine's telemetry — the abstraction the organ views hang from.
public protocol TelemetrySource: Sendable {
    func snapshot() async throws -> MachineTelemetry
}

/// Remote source: detects the OS if unknown, then runs the matching probe.
public struct RemoteSource: TelemetrySource {
    let ssh: SSHRunner
    let os: Machine.OS

    public init(ssh: SSHRunner, os: Machine.OS) {
        self.ssh = ssh
        self.os = os
    }

    public func snapshot() async throws -> MachineTelemetry {
        let effectiveOS = os == .unknown ? await ssh.detectOS() : os
        switch effectiveOS {
        case .windows:
            let out = try await ssh.run(WindowsProbe.script, shell: .powershell)
            guard let t = WindowsProbe.parse(out) else {
                throw SSHRunner.SSHError.unreachable("\(ssh.user)@\(ssh.host) — Windows probe returned no data")
            }
            return t
        default: // linux / macOS remote — both bash + coreutils-ish
            let out = try await ssh.run(LinuxProbe.script, shell: .bash)
            guard let t = LinuxProbe.parse(out) else {
                throw SSHRunner.SSHError.unreachable("\(ssh.user)@\(ssh.host) — probe returned no data")
            }
            return t
        }
    }
}
