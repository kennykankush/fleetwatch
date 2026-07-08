import Foundation

/// Runs a command on a remote machine over SSH — agentless, using the user's
/// existing keys/agent (BatchMode: never prompts for a password, fails fast
/// instead). This is the whole remote-telemetry transport.
public struct SSHRunner: Sendable {
    public let host: String
    public let user: String
    public let connectTimeout: Int

    public init(host: String, user: String, connectTimeout: Int = 8) {
        self.host = host
        self.user = user
        self.connectTimeout = connectTimeout
    }

    public enum SSHError: Error, LocalizedError {
        case unreachable(String)
        public var errorDescription: String? {
            switch self { case .unreachable(let s): "Couldn't reach \(s)" }
        }
    }

    /// Pipes `script` to `bash -s` on the remote and returns stdout.
    public func run(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = [
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=\(connectTimeout)",
                "-o", "StrictHostKeyChecking=accept-new",
                "\(user)@\(host)", "bash -s",
            ]
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
                stdin.fileHandleForWriting.write(Data(script.utf8))
                stdin.fileHandleForWriting.closeFile()
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

    /// Reachability check — cheap, for the offline/online dot.
    public func ping() async -> Bool {
        (try? await run("echo ok"))?.contains("ok") ?? false
    }
}

/// Reads a machine's telemetry — the abstraction the organ views hang from.
/// Local uses native reads (elsewhere); remote uses SSH + probe parse.
public protocol TelemetrySource: Sendable {
    func snapshot() async throws -> MachineTelemetry
}

/// Remote Linux source: run the probe over SSH, parse the output.
public struct RemoteLinuxSource: TelemetrySource {
    let ssh: SSHRunner
    public init(ssh: SSHRunner) { self.ssh = ssh }

    public func snapshot() async throws -> MachineTelemetry {
        let output = try await ssh.run(LinuxProbe.script)
        guard let telemetry = LinuxProbe.parse(output) else {
            throw SSHRunner.SSHError.unreachable("\(ssh.user)@\(ssh.host) — probe returned no data")
        }
        return telemetry
    }
}
