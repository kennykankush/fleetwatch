import SwiftUI

/// The standard surface: flat fill, hairline edge, consistent radius.
/// Glass is reserved for the Overview hero — everything else stays quiet.
struct Card<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
    }
}

/// The hero surface: the one place liquid glass is allowed.
struct HeroCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.09), lineWidth: 1)
            }
    }
}

/// A small tinted icon container — the leading element of rows and tiles.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// A colored dot + label, for legends.
struct LegendDot: View {
    let color: Color
    let label: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.medium))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// Compact capsule badge, tier- or source-tinted.
struct TierBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// A stat tile for the Overview grid.
struct StatTile: View {
    let symbol: String
    let tint: Color
    let label: String
    let value: String
    let caption: String

    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    IconTile(symbol: symbol, tint: tint, size: 26)
                    Text(label.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.0)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
