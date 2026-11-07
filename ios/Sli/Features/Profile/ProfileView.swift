import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    stats
                    SectionHeader(title: "Weekly challenges", trailing: "Resets Mon")
                    VStack(spacing: 10) { ForEach(state.challenges) { ChallengeRow(challenge: $0) } }
                    SectionHeader(title: "Badges", trailing: "\(state.profile.badges.filter { $0.progress >= 1 }.count)/\(state.profile.badges.count)")
                    badges
                    SectionHeader(title: "Friends leaderboard", trailing: "This week")
                    leaderboard
                    SectionHeader(title: "Wallet")
                    wallet
                }
                .padding()
            }
            .background(AuroraBackground())
            .navigationTitle("You")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "gearshape.fill") }
                }
            }
        }
    }

    private var hero: some View {
        let p = state.profile
        return HStack(spacing: 20) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 10)
                Circle().trim(from: 0, to: p.levelProgress)
                    .stroke(AngularGradient(colors: [Theme.accent, Theme.gold, Theme.accent], center: .center),
                            style: .init(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("LV").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                    Text("\(p.level)").font(.system(size: 38, weight: .heavy, design: .rounded))
                }
            }
            .frame(width: 104, height: 104)
            .padding(10)
            .glassEffect(.regular.tint(Theme.accent.opacity(0.2)), in: .circle)

            VStack(alignment: .leading, spacing: 6) {
                Text(p.name).font(.title2.weight(.bold)).fontDesign(.rounded)
                Text("@\(p.handle)").font(.subheadline).foregroundStyle(.secondary)
                Text("\(p.xpToNext) XP to level \(p.level + 1)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .glassEffect(.regular.tint(Theme.gold.opacity(0.35)), in: .capsule)
            }
        }
    }

    private var stats: some View {
        let p = state.profile
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(value: "\(p.streakDays)", label: "Day streak", symbol: "flame.fill", tint: Theme.ember)
                StatTile(value: "\(p.tripsThisWeek)", label: "Trips this week", symbol: "tram.fill", tint: TransitMode.luas.color)
            }
            GridRow {
                StatTile(value: String(format: "%.0f kg", p.co2SavedKg), label: "CO₂ saved", symbol: "leaf.fill", tint: Theme.accent)
                StatTile(value: "\(p.totalTrips)", label: "Lifetime trips", symbol: "point.3.connected.trianglepath.dotted", tint: Theme.violet)
            }
        }
    }

    private var badges: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            ForEach(state.profile.badges) { b in
                VStack(spacing: 8) {
                    ZStack {
                        Circle().trim(from: 0, to: b.progress).stroke(b.tint, style: .init(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: b.symbol).font(.title2)
                            .foregroundStyle(b.progress >= 1 ? b.tint : .secondary)
                    }
                    .frame(width: 56, height: 56)
                    Text(b.title).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 116)
                .glassEffect(b.progress >= 1 ? .regular.tint(b.tint.opacity(0.2)).interactive() : .regular.interactive(),
                             in: .rect(cornerRadius: 22))
                .saturation(b.progress >= 1 ? 1 : 0.3)
            }
        }
    }

    private var leaderboard: some View {
        GlassCard {
            VStack(spacing: 12) {
                ForEach(Array(state.leaderboard.enumerated()), id: \.offset) { i, entry in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(.headline.weight(.heavy)).fontDesign(.rounded).frame(width: 24)
                            .foregroundStyle(i == 0 ? Theme.gold : i == 1 ? .gray : i == 2 ? .brown : .secondary)
                        AvatarView(name: entry.name, seed: entry.seed, size: 34)
                        Text(entry.isMe ? "You" : entry.name).font(.subheadline.weight(entry.isMe ? .bold : .medium))
                        Spacer()
                        Text("\(entry.xp) XP").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(entry.isMe ? Theme.accent.opacity(0.15) : .clear, in: .rect(cornerRadius: 12))
                }
            }
        }
    }

    private var wallet: some View {
        VStack(spacing: 12) {
            Button { TicketingHandoff.open(.leapTopUp) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "creditcard.fill").font(.title2)
                        .frame(width: 48, height: 48)
                        .background(Theme.heroGradient, in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading) {
                        Text("Top up Leap Card").font(.headline)
                        Text("Opens the official Leap Top-Up app").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))

            Button { TicketingHandoff.open(.tfiGo) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "qrcode").font(.title2)
                        .frame(width: 48, height: 48)
                        .background(LinearGradient(colors: [Theme.violet, .indigo], startPoint: .top, endPoint: .bottom),
                                    in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading) {
                        Text("Buy a TFI Go ticket").font(.headline)
                        Text("Mobile tickets for bus & rail").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        }
    }
}

private struct ChallengeRow: View {
    let challenge: Challenge

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: challenge.symbol).font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.tint(Theme.accent.opacity(0.25)), in: .circle)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(challenge.title).font(.headline)
                    Spacer()
                    Text("+\(challenge.rewardXP) XP").font(.caption.weight(.heavy)).foregroundStyle(Theme.gold)
                }
                Text(challenge.detail).font(.caption).foregroundStyle(.secondary)
                ProgressView(value: Double(challenge.progress), total: Double(challenge.goal)).tint(Theme.accent)
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}
