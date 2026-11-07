import SwiftUI

struct StopDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let stop: Stop
    @State private var arrivals: [Arrival] = []
    @State private var tracking: String?

    private var friendsHere: [Friend] {
        state.friends.filter {
            if case let .onTransit(_, route, _, _) = $0.status { return stop.routes.contains(route) }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !friendsHere.isEmpty { friendsBanner }
                    VStack(spacing: 10) {
                        ForEach(arrivals) { arrival in
                            ArrivalRow(arrival: arrival, tracking: tracking == arrival.id) {
                                withAnimation(.bouncy) { tracking = tracking == arrival.id ? nil : arrival.id }
                            }
                        }
                    }
                    ticketButtons
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { state.toggleFavourite(stop) } label: {
                        Image(systemName: state.favouriteStopIDs.contains(stop.id) ? "star.fill" : "star")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .tint(Theme.gold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task { arrivals = (try? await state.transit.arrivals(for: stop)) ?? [] }
            .refreshable { arrivals = (try? await state.transit.arrivals(for: stop)) ?? [] }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(stop.modes, id: \.self) { ModeBadge(mode: $0) }
                Text("Stop \(stop.code)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(stop.name).font(.largeTitle.weight(.bold)).fontDesign(.rounded)
            HStack(spacing: 6) {
                let live = arrivals.filter(\.isLive).count
                if live > 0 { LivePulse() } else { Image(systemName: "calendar").font(.caption) }
                Text(live > 0 ? "\(live) tracked live · \(arrivals.count - live) timetable only"
                              : "Timetable times only, nothing tracked yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Source: \(state.transit.sourceLabel)").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var friendsBanner: some View {
        GlassCard(tint: Theme.accent) {
            HStack(spacing: -8) {
                ForEach(friendsHere) { AvatarView(name: $0.name, seed: $0.seed, size: 32) }
                Text("\(friendsHere.map { $0.name.components(separatedBy: " ").first ?? "" }.joined(separator: ", ")) on a route from here")
                    .font(.subheadline.weight(.medium))
                    .padding(.leading, 16)
            }
        }
    }

    private var ticketButtons: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button { TicketingHandoff.open(.leapTopUp) } label: {
                    Label("Top up Leap", systemImage: "creditcard.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button { TicketingHandoff.open(.tfiGo) } label: {
                    Label("TFI Go ticket", systemImage: "qrcode").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
    }
}

private struct ArrivalRow: View {
    let arrival: Arrival
    let tracking: Bool
    let onTrack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ModeBadge(mode: arrival.mode, route: arrival.route)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(arrival.headsign).font(.headline).lineLimit(1)
                    .strikethrough(arrival.status == .cancelled)
                HStack(spacing: 6) {
                    StatusChip(status: arrival.status, delayMinutes: arrival.delayMinutes)
                    if let crowding = arrival.crowding { CrowdingBar(level: crowding) }
                }
            }
            Spacer()
            MinutesLabel(minutes: arrival.minutes, isLive: arrival.isLive)
            Button(action: onTrack) {
                Image(systemName: tracking ? "bell.badge.fill" : "bell")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .glassEffect(tracking ? .regular.tint(Theme.accent).interactive() : .regular.interactive(), in: .circle)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .sensoryFeedback(.selection, trigger: tracking)
    }
}

private struct CrowdingBar: View {
    let level: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Double(i) / 3 < level ? color : .secondary.opacity(0.3))
            }
            Text(level < 0.4 ? "Quiet" : level < 0.75 ? "Busy" : "Packed")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var color: Color { level < 0.4 ? Theme.accent : level < 0.75 ? Theme.gold : Theme.ember }
}
