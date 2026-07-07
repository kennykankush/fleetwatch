import SwiftUI
import ScannerKit
import RulesKit
import LedgerKit

/// Shared reclaimable state — built once, observed by Overview and Caches.
@MainActor
@Observable
final class ReclaimableModel {
    static let shared = ReclaimableModel()

    var items: [ReclaimableItem] = []
    var isLoading = false
    private var loaded = false

    var totals: [Tier: Int64] { ReclaimableIndex.totals(of: items) }
    var grandTotal: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    func loadIfNeeded() async {
        guard !loaded, !isLoading else { return }
        await build()
        loaded = true
    }

    func refresh() async {
        // Forget measurements for every listed location, then re-measure.
        for item in items {
            await SizeCache.shared.invalidate(subtree: item.path)
        }
        await build()
    }

    /// The core promise: move to Trash, record it, forget the measurement.
    /// Returns the ledger description, or throws.
    func clear(_ item: ReclaimableItem) async throws -> String {
        try TrashAction.moveToTrash(path: item.path)
        await SizeCache.shared.invalidate(subtree: item.path)
        await SizeCache.shared.flush()
        items.removeAll { $0.id == item.id }
        let description = "\(item.rule.title) (\(item.sizeBytes.bytesFormatted)) moved to Trash — recoverable. \(item.rule.regeneration)"
        await LedgerStore.shared.append(LedgerEvent(
            kind: .cleared,
            title: "Cleared \(item.rule.title)",
            detail: description,
            bytes: item.sizeBytes
        ))
        return description
    }

    private func build() async {
        isLoading = true
        if let registry = try? RulesRegistry.bundled() {
            let index = ReclaimableIndex(registry: registry)
            items = await index.build()
        }
        isLoading = false
        // Keep the widget's reclaimable number current.
        if let accounting = try? DiskAccounting.measure() {
            WidgetBridge.export(accounting: accounting, reclaimable: grandTotal)
        }
    }
}

/// The cache sector: everything Stockpile recognizes as reclaimable,
/// found for you — no descending required.
struct CachesView: View {
    @State private var model = ReclaimableModel.shared
    @State private var pendingClear: ReclaimableItem?
    @State private var lastAction: String?
    @State private var clearError: String?

    var body: some View {
        Screen(
            title: "Caches",
            subtitle: "Every reclaimable location the registry recognizes — found for you.",
            actions: {
                BarButton(label: "Refresh", symbol: "arrow.clockwise", disabled: model.isLoading) {
                    Task { await model.refresh() }
                }
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionGap) {
                    if let lastAction {
                        Card(padding: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.tierCache)
                                Text(lastAction)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Dismiss") { self.lastAction = nil }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if let clearError {
                        Card(padding: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.tierRegenerable)
                                Text(clearError)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Dismiss") { self.clearError = nil }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    if model.isLoading && model.items.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Finding reclaimable space…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        StatStrip(columns: [
                            .init(
                                label: "Free to clear",
                                value: (model.totals[.cache] ?? 0).bytesFormatted,
                                caption: "Pure caches — clearing costs nothing.",
                                tint: Theme.tierCache
                            ),
                            .init(
                                label: "If you rebuild",
                                value: (model.totals[.regenerable] ?? 0).bytesFormatted,
                                caption: "Build artifacts and dependencies — one install away.",
                                tint: Theme.tierRegenerable
                            ),
                        ])
                        tierSection(.cache, label: "Free to clear", caption: "regenerates itself — zero cost")
                        tierSection(.regenerable, label: "Costs a rebuild", caption: "restorable with a reinstall or recompile")
                    }
                }
                .padding(28)
            }
        }
        .task { await model.loadIfNeeded() }
        .confirmationDialog(
            pendingClear.map { "Clear \($0.rule.title)? (\($0.sizeBytes.bytesFormatted))" } ?? "",
            isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
            titleVisibility: .visible
        ) {
            if let item = pendingClear {
                if let owner = item.rule.ownerAppBundleID, let running = RunningApps.app(bundleID: owner) {
                    Button("Quit \(running.localizedName ?? "app") & Clear", role: .destructive) {
                        perform(item, quitting: running)
                    }
                } else {
                    Button("Move to Trash", role: .destructive) {
                        perform(item, quitting: nil)
                    }
                }
                Button("Cancel", role: .cancel) { pendingClear = nil }
            }
        } message: {
            if let item = pendingClear {
                Text("\(item.rule.regeneration) Moved to Trash — recoverable until you empty it.")
            }
        }
    }

    private func perform(_ item: ReclaimableItem, quitting owner: NSRunningApplication?) {
        pendingClear = nil
        Task {
            if let owner {
                owner.terminate()
                try? await Task.sleep(for: .seconds(1))
            }
            do {
                lastAction = try await model.clear(item)
                clearError = nil
            } catch {
                clearError = "Couldn't clear \(item.rule.title): \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func tierSection(_ tier: Tier, label: String, caption: String) -> some View {
        let items = model.items.filter { $0.rule.tier == tier }
        if !items.isEmpty {
            let largest = items.map(\.sizeBytes).max() ?? 1
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: label, trailing: caption)
                Card(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ReclaimableRow(
                                item: item,
                                fractionOfLargest: largest > 0 ? Double(item.sizeBytes) / Double(largest) : 0
                            ) { pendingClear = item }
                            if index < items.count - 1 {
                                Divider().overlay(Theme.hairline).padding(.leading, 50)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ReclaimableRow: View {
    let item: ReclaimableItem
    let fractionOfLargest: Double
    let onClear: () -> Void
    @State private var hovering = false

    private var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return item.path.hasPrefix(home)
            ? "~" + item.path.dropFirst(home.count)
            : item.path
    }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(
                symbol: item.rule.tier == .cache ? "leaf" : "hammer",
                tint: item.rule.tier.color,
                size: 26
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(item.rule.title)
                    .font(.system(size: 13, weight: .medium))
                Text(abbreviatedPath)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if hovering {
                Text(item.rule.regeneration)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            SizeBar(fraction: fractionOfLargest, tint: item.rule.tier.color.opacity(0.75))
            Text(item.sizeBytes.bytesFormatted)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)

            Button(action: onClear) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hovering ? Theme.tierData : Color.white.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .background(hovering ? Theme.surface2 : .clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(Pressable())
            .help("Move to Trash — recoverable")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(item.rule.explanation)
    }
}
