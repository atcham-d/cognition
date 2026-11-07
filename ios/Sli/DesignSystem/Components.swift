import SwiftUI

struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = Theme.spacing
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular,
                         in: .rect(cornerRadius: Theme.cardRadius))
    }
}

struct ModeBadge: View {
    let mode: TransitMode
    var route: String? = nil
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mode.symbol)
            if let route { Text(route).fontWeight(.heavy) }
        }
        .font(compact ? .caption2 : .caption)
        .fontDesign(.rounded)
        .foregroundStyle(mode.foreground)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(mode.color, in: .capsule)
    }
}

struct AvatarView: View {
    let name: String
    var seed: Int = 0
    var size: CGFloat = 44
    var ring: Color? = nil

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.avatarGradient(seed), in: .circle)
            .overlay {
                if let ring {
                    Circle().strokeBorder(ring, lineWidth: max(2, size * 0.06))
                        .padding(-size * 0.08)
                }
            }
    }
}

struct LivePulse: View {
    var color: Color = Theme.accent
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background(Circle().fill(color.opacity(0.4)).scaleEffect(on ? 2.4 : 1).opacity(on ? 0 : 1))
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating.speed(0.4))
            Text(value)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.18)), in: .rect(cornerRadius: 22))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold)).fontDesign(.rounded)
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline.weight(.medium)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct MinutesLabel: View {
    let minutes: Int
    var isLive = true

    var body: some View {
        HStack(spacing: 6) {
            if isLive { LivePulse() }
            if minutes <= 0 {
                Text("Due").font(.headline.weight(.heavy)).foregroundStyle(Theme.accent)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(minutes)").font(.title3.weight(.heavy)).contentTransition(.numericText())
                    Text("min").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .fontDesign(.rounded)
    }
}
