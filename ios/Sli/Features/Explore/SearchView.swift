import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var selectedStop: Stop?

    private var stops: [Stop] {
        query.isEmpty ? state.stops : state.stops.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.routes.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var friends: [Friend] {
        query.isEmpty ? [] : state.friends.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.handle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty, !state.favouriteStops.isEmpty {
                    Section("Favourites") { ForEach(state.favouriteStops) { stopRow($0) } }
                }
                if !friends.isEmpty {
                    Section("Friends") {
                        ForEach(friends) { f in
                            HStack(spacing: 12) {
                                AvatarView(name: f.name, seed: f.seed, size: 36, ring: f.ringColor)
                                VStack(alignment: .leading) {
                                    Text(f.name).font(.headline)
                                    Text(f.status.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section(query.isEmpty ? "Nearby" : "Stops & routes") { ForEach(stops) { stopRow($0) } }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Stops, routes, friends")
            .sheet(item: $selectedStop) { StopDetailView(stop: $0).presentationDetents([.medium, .large]) }
        }
    }

    private func stopRow(_ stop: Stop) -> some View {
        Button { selectedStop = stop } label: {
            HStack(spacing: 12) {
                Image(systemName: stop.primaryMode.symbol)
                    .foregroundStyle(stop.primaryMode.foreground)
                    .frame(width: 34, height: 34)
                    .background(stop.primaryMode.color, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading) {
                    Text(stop.name).font(.headline)
                    Text(stop.routes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }
}
