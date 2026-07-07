import SwiftUI
import RulesKit

/// Stockpile's design tokens. Premium restraint: one accent, semantic color
/// only, hairlines over glows, an 8pt grid.
enum Theme {
    // MARK: Color
    static let accent = Color(red: 0.39, green: 0.88, blue: 0.76)
    static let purgeable = Color(red: 0.48, green: 0.62, blue: 0.86)
    static let tierCache = Color(red: 0.45, green: 0.83, blue: 0.55)
    static let tierRegenerable = Color(red: 0.93, green: 0.72, blue: 0.38)
    static let tierData = Color(red: 0.91, green: 0.47, blue: 0.51)

    static let background = Color(red: 0.043, green: 0.043, blue: 0.051)
    static let surface = Color.white.opacity(0.035)
    static let surfaceHover = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.07)

    // MARK: Metrics
    static let radiusCard: CGFloat = 14
    static let radiusRow: CGFloat = 10
    static let pagePadding: CGFloat = 32
    static let sectionGap: CGFloat = 24
}

extension Tier {
    var color: Color {
        switch self {
        case .cache: Theme.tierCache
        case .regenerable: Theme.tierRegenerable
        }
    }

    var badgeLabel: String {
        switch self {
        case .cache: "Cache"
        case .regenerable: "Regenerable"
        }
    }
}

extension Int64 {
    var bytesFormatted: String {
        self.formatted(.byteCount(style: .file))
    }
}

/// Flat near-black backdrop with a barely-there bloom — surfaces define
/// themselves with hairlines, not glow.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.accent.opacity(0.045), .clear],
                center: .init(x: 0.15, y: -0.1),
                startRadius: 0,
                endRadius: 900
            )
        }
        .ignoresSafeArea()
    }
}

/// Page header used by every section: title, one-line subtitle.
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.4)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Small-caps section label above a card.
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 2)
    }
}
