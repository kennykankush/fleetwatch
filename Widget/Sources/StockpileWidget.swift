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

    static let sample = DiskSnapshot(
        date: .now, physicalUsedFraction: 0.66, effectiveUsedFraction: 0.37,
        physicalFree: 165_000_000_000, purgeable: 146_000_000_000, reclaimable: 48_000_000_000
    )
}

struct DiskEntry: TimelineEntry {
    let date: Date
    let snapshot: DiskSnapshot?
}

struct DiskProvider: TimelineProvider {
    private static let groupID = "483LU3J5WJ.com.hadimulia.stockpile"

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
                    Text("Open Stockpile once")
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
            HStack(spacing: 10) {
                Text("\(s.physicalFree.formatted(.byteCount(style: .file))) strictly free")
                Text("·").foregroundStyle(.tertiary)
                Text("\(s.purgeable.formatted(.byteCount(style: .file))) purgeable")
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

@main
struct StockpileWidgets: WidgetBundle {
    var body: some Widget {
        HonestDiskWidget()
    }
}
