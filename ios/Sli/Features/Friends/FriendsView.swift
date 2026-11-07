import SwiftUI
import MapKit

struct FriendsView: View {
    @Environment(AppState.self) private var state
    @State private var position: MapCameraPosition = .region(.init(
        center: .init(latitude: 53.3465, longitude: -6.2600),
        span: .init(latitudeDelta: 0.03, longitudeDelta: 0.03)))
    @State private var focused: Friend?

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    map
                    VStack(alignment: .leading, spacing: 20) {
                        sharingControl($state.shareMode)
                        SectionHeader(title: "On the move", trailing: "\(moving.count)")
                        ForEach(moving) { FriendRow(friend: $0) { focus($0) } }
                        SectionHeader(title: "Everyone else")
                        ForEach(still) { FriendRow(friend: $0) { focus($0) } }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }
            .background(AuroraBackground(tint: Theme.violet))
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { } label: { Image(systemName: "person.badge.plus") }
                }
            }
        }
    }

    private var moving: [Friend] {
        state.friends.filter { if case .onTransit = $0.status { true } else { false } }
    }
    private var still: [Friend] { state.friends.filter { !moving.contains($0) } }

    private func focus(_ f: Friend) {
        withAnimation(.smooth(duration: 0.8)) {
            focused = f
            position = .region(.init(center: f.location.coordinate, span: .init(latitudeDelta: 0.008, longitudeDelta: 0.008)))
        }
    }

    private var map: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(state.friends.filter { $0.status != .offline }) { f in
                Annotation(f.name, coordinate: f.location.coordinate) {
                    VStack(spacing: 4) {
                        AvatarView(name: f.name, seed: f.seed, size: focused == f ? 48 : 38, ring: f.ringColor ?? .white)
                        if case let .onTransit(mode, route, _, _) = f.status {
                            ModeBadge(mode: mode, route: route, compact: true)
                        }
                    }
                    .shadow(radius: 8)
                    .animation(.bouncy, value: focused)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .frame(height: 340)
        .clipShape(.rect(cornerRadius: 36))
        .padding(.horizontal, 8)
    }

    private func sharingControl(_ mode: Binding<ShareMode>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your location").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(ShareMode.allCases) { m in
                        Button { withAnimation(.bouncy) { mode.wrappedValue = m } } label: {
                            Label(m.title, systemImage: m.symbol)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(mode.wrappedValue == m
                                     ? .regular.tint((m == .paused ? Color.gray : Theme.accent).opacity(0.7)).interactive()
                                     : .regular.interactive(), in: .capsule)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: mode.wrappedValue)
        }
    }
}

private struct FriendRow: View {
    let friend: Friend
    let onTap: (Friend) -> Void

    var body: some View {
        Button { onTap(friend) } label: {
            HStack(spacing: 12) {
                AvatarView(name: friend.name, seed: friend.seed, size: 46, ring: friend.ringColor)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(friend.name).font(.headline)
                        if friend.streak > 0 {
                            Label("\(friend.streak)", systemImage: "flame.fill")
                                .font(.caption2.weight(.bold)).foregroundStyle(Theme.ember)
                        }
                    }
                    Text(friend.status.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text("Lv \(friend.level)")
                    .font(.caption.weight(.heavy)).fontDesign(.rounded)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(.regular.tint(Theme.gold.opacity(0.3)), in: .capsule)
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        .opacity(friend.status == .offline ? 0.55 : 1)
    }
}
