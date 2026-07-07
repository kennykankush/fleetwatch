import SwiftUI
import LedgerKit

/// The app's memory: every snapshot and every action, newest first.
struct LedgerView: View {
    @State private var events: [LedgerEvent] = []
    @State private var loaded = false

    private var grouped: [(day: String, events: [LedgerEvent])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: events.reversed()) { event in
            calendar.startOfDay(for: event.date)
        }
        return groups.keys.sorted(by: >).map { day in
            (
                day: day.formatted(date: .abbreviated, time: .omitted),
                events: groups[day]!.sorted { $0.date > $1.date }
            )
        }
    }

    var body: some View {
        Screen(
            title: "Ledger",
            subtitle: "Every snapshot and every action, recorded. Storage with a memory."
        ) {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sectionGap) {
                if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if events.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("No history yet", systemImage: "book.closed")
                                .font(.callout.weight(.medium))
                            Text("Snapshots record automatically each launch; actions land here the moment they happen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(grouped, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: group.day)
                            Card(padding: 6) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.events.enumerated()), id: \.element.id) { index, event in
                                        LedgerRow(event: event)
                                        if index < group.events.count - 1 {
                                            Divider().overlay(Theme.hairline).padding(.leading, 50)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        }
        .task {
            events = await LedgerStore.shared.events()
            loaded = true
        }
    }
}

private struct LedgerRow: View {
    let event: LedgerEvent

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .medium))
                Text(event.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let bytes = event.bytes {
                    Text(bytes.bytesFormatted)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Text(event.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var symbol: String {
        switch event.kind {
        case .snapshot: "gauge.with.dots.needle.50percent"
        case .startup: "power"
        case .cleared: "trash"
        }
    }

    private var tint: Color {
        switch event.kind {
        case .snapshot: Theme.purgeable
        case .startup: Theme.tierRegenerable
        case .cleared: Theme.tierCache
        }
    }
}
