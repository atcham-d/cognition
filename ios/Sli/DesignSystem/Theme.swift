import SwiftUI

enum Theme {
    static let accent = Color(red: 0.0, green: 0.80, blue: 0.56)
    static let accentDeep = Color(red: 0.0, green: 0.42, blue: 0.36)
    static let ember = Color(red: 1.0, green: 0.48, blue: 0.22)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.24)
    static let violet = Color(red: 0.52, green: 0.36, blue: 1.0)

    static let cardRadius: CGFloat = 28
    static let spacing: CGFloat = 16

    static let heroGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func avatarGradient(_ seed: Int) -> LinearGradient {
        let palettes: [[Color]] = [
            [accent, .teal], [ember, .pink], [violet, .indigo],
            [gold, ember], [.cyan, .blue], [.pink, violet]
        ]
        let colors = palettes[abs(seed) % palettes.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct AuroraBackground: View {
    var tint: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t / 4)) * 0.12
            let c = Float(cos(t / 5)) * 0.12
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + s, 0.5 + c], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    tint.opacity(0.55), .black, Theme.violet.opacity(0.35),
                    .black, tint.opacity(0.25), .black,
                    Theme.accentDeep.opacity(0.4), .black, Theme.ember.opacity(0.2)
                ]
            )
        }
        .ignoresSafeArea()
    }
}
