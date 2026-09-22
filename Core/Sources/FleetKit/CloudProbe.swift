import Foundation

/// Reads live cloud usage through the user's own `rclone` config.
///
/// The same bargain the SSH path makes: Fleetwatch stores no cloud credential
/// and runs no OAuth flow. If you already have `rclone` configured — it holds
/// the tokens — Fleetwatch can ask it how full a remote is. If you don't, a
/// drive still counts toward the fleet at its declared capacity; only the
/// live usage number is missing, and the UI says so instead of inventing one.
public enum CloudProbe {
    /// Quota as reported by the provider. Every field is optional because
    /// plenty of backends implement only some of them (and a few — bare S3,
    /// for instance — support `about` not at all).
    public struct Usage: Sendable, Hashable {
        public let total: Int64?
        public let used: Int64?
        public let free: Int64?
        public let trashed: Int64?

        public init(total: Int64?, used: Int64?, free: Int64?, trashed: Int64? = nil) {
            self.total = total; self.used = used; self.free = free; self.trashed = trashed
        }
    }

    public enum ProbeError: Error, LocalizedError {
        case rcloneMissing
        case unsupported(String)
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .rcloneMissing: "rclone isn't installed — declare the capacity instead, or `brew install rclone`."
            case .unsupported(let r): "\(r) doesn't report usage (the backend has no `about` support)."
            case .failed(let m): m
            }
        }
    }

    /// Homebrew (Apple silicon, Intel) then system paths. A GUI app doesn't
    /// inherit the shell's PATH, so guessing well matters more than `which`.
    static let searchPaths = [
        "/opt/homebrew/bin/rclone",
        "/usr/local/bin/rclone",
        "/usr/bin/rclone",
    ]

    public static var executablePath: String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var isAvailable: Bool { executablePath != nil }

    /// Configured remote names, colon included (`gdrive:`, `onedrive:`).
    public static func listRemotes() async -> [String] {
        guard let out = try? await run(["listremotes"]) else { return [] }
        return out.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `rclone about <remote> --json` → parsed quota.
    public static func about(remote: String) async throws -> Usage {
        let name = remote.hasSuffix(":") ? remote : remote + ":"
        let out = try await run(["about", name, "--json"])
        guard let usage = parse(out) else { throw ProbeError.unsupported(name) }
        return usage
    }

    /// Parses `rclone about --json`. Fields are optional and arrive as JSON
    /// numbers; anything missing stays `nil` rather than becoming zero.
    public static func parse(_ json: String) -> Usage? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        func field(_ key: String) -> Int64? {
            if let n = obj[key] as? NSNumber { return n.int64Value }
            if let s = obj[key] as? String { return Int64(s) }
            return nil
        }
        let usage = Usage(total: field("total"), used: field("used"),
                          free: field("free"), trashed: field("trashed"))
        // An object with none of the interesting fields is not a usable answer.
        guard usage.total != nil || usage.used != nil || usage.free != nil else { return nil }
        return usage
    }

    private static func run(_ arguments: [String]) async throws -> String {
        guard let path = executablePath else { throw ProbeError.rcloneMissing }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let stdout = Pipe(), stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "rclone failed"
                    continuation.resume(throwing: ProbeError.failed(message.isEmpty ? "rclone failed" : message))
                } else {
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                }
            } catch {
                continuation.resume(throwing: ProbeError.failed(error.localizedDescription))
            }
        }
    }
}
