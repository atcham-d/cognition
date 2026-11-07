import SwiftUI
import MapKit

struct ExploreView: View {
    @Environment(AppState.self) private var state
    @State private var position: MapCameraPosition = .region(.init(
        center: .init(latitude: 53.3465, longitude: -6.2580),
        span: .init(latitudeDelta: 0.025, longitudeDelta: 0.025)))
    @State private var selectedStop: Stop?
    @State private var showFriends = true
    @State private var modeFilter: TransitMode?
    @Namespace private var glass

    private var visibleStops: [Stop] {
        guard let modeFilter else { return state.stops }
        return state.stops.filter { $0.modes.contains(modeFilter) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                UserAnnotation()
                ForEach(visibleStops) { stop in
                    Annotation(stop.name, coordinate: stop.location.coordinate, anchor: .bottom) {
                        StopPin(stop: stop, selected: selectedStop?.id == stop.id)
                            .onTapGesture { selectedStop = stop }
                    }
                    .annotationTitles(.hidden)
                }
                if showFriends {
                    ForEach(state.friends.filter { $0.status != .offline }) { friend in
                        Annotation(friend.name, coordinate: friend.location.coordinate) {
                            AvatarView(name: friend.name, seed: friend.seed, size: 34, ring: friend.ringColor ?? .white)
                                .shadow(radius: 6)
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls { MapCompass() }
            .ignoresSafeArea()

            topBar
        }
        .safeAreaInset(edge: .bottom) { stopCarousel }
        .sheet(item: $selectedStop) { stop in
            StopDetailView(stop: stop)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    filterChip(nil, title: "All", symbol: "square.grid.2x2.fill")
                    ForEach(TransitMode.allCases, id: \.self) { mode in
                        filterChip(mode, title: mode.title, symbol: mode.symbol)
                    }
                }
            }
            Spacer()
            GlassEffectContainer(spacing: 0) {
                VStack(spacing: 0) {
                    Button { withAnimation { position = .userLocation(fallback: position) } } label: {
                        Image(systemName: "location.fill").frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive())
                    .glassEffectUnion(id: "controls", namespace: glass)
                    Button { withAnimation(.bouncy) { showFriends.toggle() } } label: {
                        Image(systemName: showFriends ? "person.2.fill" : "person.2.slash")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive())
                    .glassEffectUnion(id: "controls", namespace: glass)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func filterChip(_ mode: TransitMode?, title: String, symbol: String) -> some View {
        let selected = modeFilter == mode
        return Button {
            withAnimation(.bouncy) { modeFilter = mode }
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? (mode?.foreground ?? .black) : .primary)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint((mode?.color ?? Theme.accent).opacity(0.9)).interactive()
                              : .regular.interactive(), in: .circle)
        .glassEffectID(title, in: glass)
        .accessibilityLabel(title)
    }

    private var stopCarousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(visibleStops) { stop in
                    Button { selectedStop = stop } label: { StopCard(stop: stop) }
                        .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .padding(.bottom, 8)
    }
}

private struct StopPin: View {
    let stop: Stop
    let selected: Bool

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: stop.primaryMode.symbol)
                .font(.system(size: selected ? 18 : 14, weight: .bold))
                .foregroundStyle(stop.primaryMode.foreground)
                .frame(width: selected ? 40 : 30, height: selected ? 40 : 30)
                .background(stop.primaryMode.color, in: .circle)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(180))
                .offset(y: -2)
        }
        .shadow(color: stop.primaryMode.color.opacity(0.6), radius: selected ? 12 : 4)
        .animation(.bouncy, value: selected)
    }
}

private struct StopCard: View {
    @Environment(AppState.self) private var state
    let stop: Stop
    @State private var arrivals: [Arrival] = []
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 4) {
                    ForEach(stop.modes, id: \.self) { ModeBadge(mode: $0, compact: true) }
                }
                Spacer()
                if state.favouriteStopIDs.contains(stop.id) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.gold).font(.caption)
                }
            }
            Text(stop.name).font(.headline).lineLimit(1)
            ForEach(arrivals.prefix(2)) { a in
                HStack {
                    Text(a.route).font(.subheadline.weight(.bold)).fontDesign(.rounded)
                    Text(a.headsign).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if !a.isLive {
                        Image(systemName: a.status.symbol).font(.caption2).foregroundStyle(a.status.color)
                            .accessibilityLabel(a.status.title)
                    }
                    MinutesLabel(minutes: a.minutes, isLive: a.isLive)
                }
            }
            if loaded && arrivals.isEmpty {
                Text("No departures in the next 90 min").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.cardRadius))
        .task {
            arrivals = (try? await state.transit.arrivals(for: stop)) ?? []
            loaded = true
        }
    }
}
