import Foundation

/// A machine in the fleet. `local` is the Mac running Fleetwatch; the rest are
/// added by raw Tailscale host + user and read over agentless SSH.
public struct Machine: Codable, Sendable, Identifiable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case local        // this Mac — native reads, full housekeeping
        case remote       // added over SSH — watch-only
    }

    public enum OS: String, Codable, Sendable {
        case macOS, linux, windows, unknown
    }

    public let id: UUID
    public var name: String
    public let kind: Kind
    /// Tailscale host or ~/.ssh alias (empty for local).
    public var host: String
    public var user: String
    public var os: OS

    public init(id: UUID = UUID(), name: String, kind: Kind, host: String = "", user: String = "", os: OS = .unknown) {
        self.id = id
        self.name = name
        self.kind = kind
        self.host = host
        self.user = user
        self.os = os
    }

    /// The always-present local machine.
    public static func thisMac(name: String) -> Machine {
        Machine(name: name, kind: .local, os: .macOS)
    }
}
