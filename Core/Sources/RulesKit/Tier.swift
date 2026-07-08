import Foundation

/// The safety verdict Fleetwatch attaches to anything it recognizes.
///
/// There is deliberately no `data` case: user data is represented by the
/// *absence* of a matching rule. The registry is an allowlist — Fleetwatch can
/// only ever suggest clearing what a rule explicitly recognizes.
public enum Tier: String, Codable, Sendable, CaseIterable, Hashable {
    /// 🟢 Pure cache — regenerates itself, clearing costs nothing.
    case cache
    /// 🟡 Regenerable — deletable, but costs a rebuild or re-download.
    case regenerable
}
