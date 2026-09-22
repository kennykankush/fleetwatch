import SwiftUI
import FleetKit

/// The cloud half of the fleet: drives you own, declared by capacity.
///
/// Deliberately thin. There is no OAuth, no token, no provider SDK — a cloud
/// drive is a name and a number until you point it at an `rclone` remote, and
/// then `rclone` (which already holds your credentials) answers for it.
@MainActor
@Observable
final class CloudStore {
    static let shared = CloudStore()

    private(set) var drives: [CloudDrive] = []
    var refreshing: Set<UUID> = []
    var lastError: [UUID: String] = [:]
    /// Remote names from `rclone listremotes`, loaded once on demand.
    private(set) var availableRemotes: [String] = []

    private let key = "fleet.clouds.v1"

    var rcloneAvailable: Bool { CloudProbe.isAvailable }

    init() { drives = load() }

    // MARK: mutation

    func add(_ drive: CloudDrive) {
        drives.append(drive)
        save()
        if drive.rcloneRemote != nil { Task { await refresh(drive) } }
    }

    func update(_ drive: CloudDrive) {
        guard let i = drives.firstIndex(where: { $0.id == drive.id }) else { return }
        drives[i] = drive
        save()
    }

    func remove(_ drive: CloudDrive) {
        drives.removeAll { $0.id == drive.id }
        lastError[drive.id] = nil
        save()
    }

    // MARK: probing

    /// Asks `rclone` how full a remote is. A drive with no remote configured
    /// keeps its declared numbers and is left alone.
    func refresh(_ drive: CloudDrive) async {
        guard let remote = drive.rcloneRemote, !remote.isEmpty else { return }
        refreshing.insert(drive.id)
        defer { refreshing.remove(drive.id) }
        do {
            let usage = try await CloudProbe.about(remote: remote)
            guard let i = drives.firstIndex(where: { $0.id == drive.id }) else { return }
            if let used = usage.used { drives[i].used = used }
            // The provider's own ceiling beats the declared one when it reports
            // one — it can't be out of date the way a typed number can.
            if let total = usage.total, total > 0 { drives[i].capacity = total }
            drives[i].lastMeasured = Date()
            lastError[drive.id] = nil
            save()
        } catch {
            lastError[drive.id] = error.localizedDescription
        }
    }

    func refreshAll() async {
        let probeable = drives.filter { $0.rcloneRemote?.isEmpty == false }
        guard !probeable.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for d in probeable { group.addTask { await self.refresh(d) } }
        }
    }

    func loadAvailableRemotes() async {
        availableRemotes = await CloudProbe.listRemotes()
    }

    // MARK: persistence

    private func load() -> [CloudDrive] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([CloudDrive].self, from: data) else { return [] }
        return list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(drives) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension CloudDrive.Provider {
    /// Each provider owns a hue on the fleet grid, the way each organ does.
    var tint: Color {
        switch self {
        case .googleDrive: Theme.metricHeat
        case .oneDrive: Theme.metricDisk
        case .dropbox: Theme.accent
        case .iCloud: Theme.inkTertiary
        case .box: Theme.metricDisk
        case .mega: Theme.danger
        case .proton: Theme.metricMemory
        case .s3, .backblaze: Theme.metricCPU
        case .other: Theme.inkTertiary
        }
    }
}
