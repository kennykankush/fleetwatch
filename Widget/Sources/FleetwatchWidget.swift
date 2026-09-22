import WidgetKit
import SwiftUI

/// The numbers the app exports to the App Group. Mirrors WidgetBridge.Snapshot.
struct DiskSnapshot: Codable {
    let date: Date
    let physicalUsedFraction: Double
    let effectiveUsedFraction: Double
    let physicalFree: Int64
    let purgeable: Int64
    let reclaimable: Int64
    var thermalRank: Int?
    var memoryUsedFraction: Double?
    var batteryHealth: Int?

    static let sample = DiskSnapshot(
        date: .now, physicalUsedFraction: 0.66, effectiveUsedFraction: 0.37,
        physicalFree: 165_000_000_000, purgeable: 146_000_000_000, reclaimable: 48_000_000_000,
        thermalRank: 1, memoryUsedFraction: 0.72, batteryHealth: 96
    )
}

/// The thermal ladder headline, mirrored (the widget can't import ThermalKit).
private let thermalHeadlines = ["Cool", "Warm", "Hot", "Throttling"]

struct DiskEntry: TimelineEntry {
    let date: Date
    let snapshot: DiskSnapshot?
}

struct DiskProvider: TimelineProvider {
    private static let groupID = "483LU3J5WJ.com.hadimulia.fleetwatch"

    func placeholder(in context: Context) -> DiskEntry {
        DiskEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DiskEntry) -> Void) {
        completion(DiskEntry(date: .now, snapshot: load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiskEntry>) -> Void) {
        let entry = DiskEntry(date: .now, snapshot: load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(1800))))
    }

    private func load() -> DiskSnapshot? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupID
        ) else { return nil }
        guard let data = try? Data(contentsOf: container.appending(path: "snapshot.json")) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(DiskSnapshot.self, from: data)
    }
}

/// The anti-gaslight disk widget: both accountings, no purgeable games.
struct DiskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DiskEntry

    private let accent = Color(red: 0.39, green: 0.88, blue: 0.76)
    private let purgeableTint = Color(red: 0.48, green: 0.62, blue: 0.86)

    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .systemMedium: medium(s)
                default: small(s)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(accent)
                    Text("Open Fleetwatch once")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(Color(red: 0.024, green: 0.027, blue: 0.033), for: .widget)
    }

    private func small(_ s: DiskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PHYSICAL")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(s.physicalUsedFraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Spacer(minLength: 0)
            bar(s).frame(height: 6)
            Text("\(s.physicalFree.formatted(.byteCount(style: .file))) free")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: DiskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                numberBlock("PHYSICAL", s.physicalUsedFraction, tint: accent)
                numberBlock("EFFECTIVE", s.effectiveUsedFraction, tint: purgeableTint)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(s.reclaimable.formatted(.byteCount(style: .file)))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                    Text("reclaimable")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            bar(s).frame(height: 7)
            glanceRow(s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The whole-machine glance — the other three organs, shrunk to a row.
    private func glanceRow(_ s: DiskSnapshot) -> some View {
        HStack(spacing: 0) {
            glanceItem("HEAT", s.thermalRank.map { thermalHeadlines[min($0, 3)] } ?? "—",
                       tint: rankTint(s.thermalRank ?? 0))
            divider
            glanceItem("MEMORY", s.memoryUsedFraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                       tint: fractionTint(s.memoryUsedFraction ?? 0))
            divider
            glanceItem("BATTERY", s.batteryHealth.map { "\($0)%" } ?? "—",
                       tint: s.batteryHealth.map { $0 >= 80 ? accent : purgeableTint } ?? .secondary)
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 22)
    }

    private func glanceItem(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(tint).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    private func rankTint(_ rank: Int) -> Color {
        switch rank { case 0: accent; case 1: purgeableTint; case 2: .orange; default: .red }
    }
    private func fractionTint(_ f: Double) -> Color {
        f > 0.9 ? .red : f > 0.75 ? .orange : accent
    }

    private func numberBlock(_ label: String, _ fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(fraction, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    private func bar(_ s: DiskSnapshot) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                Capsule().fill(accent)
                    .frame(width: geo.size.width * s.effectiveUsedFraction)
                Capsule().fill(purgeableTint.opacity(0.45))
                    .frame(width: geo.size.width * max(0, s.physicalUsedFraction - s.effectiveUsedFraction))
                Capsule().fill(.white.opacity(0.08))
            }
        }
    }
}

struct HonestDiskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HonestDisk", provider: DiskProvider()) { entry in
            DiskWidgetView(entry: entry)
        }
        .configurationDisplayName("Your disk, honestly")
        .description("Physical and effective usage side by side — no purgeable games.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Fleet strength

/// Mirrors WidgetBridge.FleetSnapshot. Written to its own file, so this
/// widget never has to care whether the disk snapshot exists.
struct FleetSnapshot: Codable {
    let date: Date
    let storageTotal: Int64
    let storageUsed: Int64
    let machineStorage: Int64
    let cloudStorage: Int64
    let cores: Int
    let ram: Int64
    let machines: Int
    let reachable: Int
    let clouds: Int
    let alerts: Int
    let stale: Int

    static let sample = FleetSnapshot(
        date: .now, storageTotal: 8_960_000_000_000, storageUsed: 2_100_000_000_000,
        machineStorage: 2_960_000_000_000, cloudStorage: 6_000_000_000_000,
        cores: 44, ram: 72_000_000_000, machines: 3, reachable: 2, clouds: 2, alerts: 0, stale: 1
    )
}

struct FleetEntry: TimelineEntry {
    let date: Date
    let snapshot: FleetSnapshot?
}

struct FleetProvider: TimelineProvider {
    private static let groupID = "483LU3J5WJ.com.hadimulia.fleetwatch"

    func placeholder(in context: Context) -> FleetEntry {
        FleetEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (FleetEntry) -> Void) {
        completion(FleetEntry(date: .now, snapshot: load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FleetEntry>) -> Void) {
        completion(Timeline(entries: [FleetEntry(date: .now, snapshot: load())],
                            policy: .after(.now.addingTimeInterval(1800))))
    }

    private func load() -> FleetSnapshot? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupID
        ) else { return nil }
        guard let data = try? Data(contentsOf: container.appending(path: "fleet.json")) else { return nil }
        return try? JSONDecoder().decode(FleetSnapshot.self, from: data)
    }
}

/// Everything you own, at a glance — including the machines that are asleep.
struct FleetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FleetEntry

    private let accent = Color(red: 0.39, green: 0.88, blue: 0.76)
    private let cloudTint = Color(red: 0.96, green: 0.70, blue: 0.35)

    var body: some View {
        Group {
            if let s = entry.snapshot {
                switch family {
                case .systemMedium: medium(s)
                default: small(s)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(accent)
                    Text("Open Fleetwatch once")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func small(_ s: FleetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("FLEET").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(.secondary)
            Text(byte(s.storageTotal))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(accent).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            Text("total capacity").font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            bar(s).frame(height: 6)
            Text("\(s.reachable)/\(s.machines) reachable\(s.clouds > 0 ? " · \(s.clouds) cloud" : "")")
                .font(.system(size: 9.5)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ s: FleetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("FLEET STRENGTH").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(byte(s.storageTotal))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(byte(s.storageTotal - s.storageUsed))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary).monospacedDigit()
                    Text("free").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            bar(s).frame(height: 7)
            HStack(spacing: 0) {
                item("CORES", "\(s.cores)")
                divider
                item("MEMORY", byte(s.ram))
                divider
                item("MACHINES", "\(s.reachable)/\(s.machines)")
                if s.clouds > 0 {
                    divider
                    item("CLOUD", byte(s.cloudStorage), tint: cloudTint)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Machines then cloud, used solid and headroom pale — the same reading
    /// as the app's capacity bar.
    private func bar(_ s: FleetSnapshot) -> some View {
        GeometryReader { geo in
            let total = Double(max(1, s.storageTotal))
            let machineUsed = Double(min(s.storageUsed, s.machineStorage))
            let machineFree = Double(s.machineStorage) - machineUsed
            let cloudUsed = Double(s.storageUsed) - machineUsed
            let cloudFree = max(0, Double(s.cloudStorage) - cloudUsed)
            HStack(spacing: 1.5) {
                Capsule().fill(accent).frame(width: geo.size.width * machineUsed / total)
                Capsule().fill(accent.opacity(0.28)).frame(width: geo.size.width * max(0, machineFree) / total)
                Capsule().fill(cloudTint).frame(width: geo.size.width * max(0, cloudUsed) / total)
                Capsule().fill(cloudTint.opacity(0.28)).frame(width: geo.size.width * cloudFree / total)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 22)
    }

    private func item(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(tint ?? .primary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 2)
    }

    private func byte(_ v: Int64) -> String { v.formatted(.byteCount(style: .file)) }
}

struct FleetStrengthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FleetStrength", provider: FleetProvider()) { entry in
            FleetWidgetView(entry: entry)
        }
        .configurationDisplayName("Fleet strength")
        .description("Every machine and cloud drive you own — including the ones that are asleep.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FleetwatchWidgets: WidgetBundle {
    var body: some Widget {
        HonestDiskWidget()
        FleetStrengthWidget()
    }
}
