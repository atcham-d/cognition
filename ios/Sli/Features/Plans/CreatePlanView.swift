import SwiftUI

struct CreatePlanView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(60 * 60 * 3)
    @State private var invited: Set<String> = []
    @State private var venue: Venue?
    @State private var vibe: Vibe = .drinks

    enum Vibe: String, CaseIterable, Identifiable {
        case drinks, food, outdoors, gig, coffee
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .drinks: "wineglass.fill"
            case .food: "fork.knife"
            case .outdoors: "figure.hiking"
            case .gig: "music.mic"
            case .coffee: "cup.and.saucer.fill"
            }
        }
        var tint: Color {
            switch self {
            case .drinks: Theme.ember
            case .food: Theme.gold
            case .outdoors: Theme.accent
            case .gig: Theme.violet
            case .coffee: .brown
            }
        }
    }

    struct Venue: Identifiable, Hashable {
        let id: String
        let name: String
        let location: GeoPoint
        let avgMinutes: Int
        let spread: Int
    }

    private let fairVenues: [Venue] = [
        .init(id: "v1", name: "Temple Bar", location: .init(lat: 53.3455, lon: -6.2642), avgMinutes: 14, spread: 3),
        .init(id: "v2", name: "Grand Canal Dock", location: .init(lat: 53.3398, lon: -6.2378), avgMinutes: 16, spread: 4),
        .init(id: "v3", name: "Smithfield", location: .init(lat: 53.3490, lon: -6.2780), avgMinutes: 18, spread: 6)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TextField("What's the plan?", text: $title)
                        .font(.title2.weight(.bold))
                        .padding(18)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))

                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(Vibe.allCases) { v in
                                Button { withAnimation(.bouncy) { vibe = v } } label: {
                                    Image(systemName: v.symbol).frame(maxWidth: .infinity, minHeight: 48)
                                }
                                .buttonStyle(.plain)
                                .glassEffect(vibe == v ? .regular.tint(v.tint).interactive() : .regular.interactive(),
                                             in: .rect(cornerRadius: 16))
                            }
                        }
                    }

                    SectionHeader(title: "Invite")
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(state.friends) { f in
                                Button {
                                    withAnimation(.bouncy) {
                                        if invited.contains(f.id) { invited.remove(f.id) } else { invited.insert(f.id) }
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        AvatarView(name: f.name, seed: f.seed, size: 56,
                                                   ring: invited.contains(f.id) ? Theme.accent : nil)
                                            .overlay(alignment: .bottomTrailing) {
                                                if invited.contains(f.id) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.white, Theme.accent).font(.title3)
                                                        .transition(.scale)
                                                }
                                            }
                                        Text(f.name.components(separatedBy: " ").first ?? "").font(.caption)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)

                    SectionHeader(title: "Fair meeting points", trailing: invited.isEmpty ? nil : "by transit")
                    VStack(spacing: 10) {
                        ForEach(fairVenues) { v in
                            Button { withAnimation(.bouncy) { venue = v } } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(vibe.tint)
                                    VStack(alignment: .leading) {
                                        Text(v.name).font(.headline)
                                        Text("~\(v.avgMinutes) min for everyone · ±\(v.spread) min")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if venue == v { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                                .padding(14)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(venue == v ? .regular.tint(vibe.tint.opacity(0.3)).interactive() : .regular.interactive(),
                                         in: .rect(cornerRadius: 20))
                        }
                    }

                    SectionHeader(title: "When")
                    DatePicker("Time", selection: $date, in: Date()...)
                        .datePickerStyle(.compact)
                        .padding(14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }
                .padding()
            }
            .navigationTitle("New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { create() }.disabled(title.isEmpty || venue == nil)
                }
            }
        }
    }

    private func create() {
        guard let venue else { return }
        let attendees = state.friends.filter { invited.contains($0.id) }
            .map { PlanAttendee(friend: $0, rsvp: .invited, etaMinutes: nil, arrived: false) }
        state.addPlan(Plan(id: UUID().uuidString, title: title, symbol: vibe.symbol, tint: vibe.tint, date: date,
                           placeName: venue.name, location: venue.location, attendees: attendees,
                           timeOptions: [.init(id: UUID().uuidString, date: date, voterIDs: ["me"])]))
        dismiss()
    }
}
