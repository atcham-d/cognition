import SwiftUI

@MainActor
@Observable
final class AppState {
    let transit: any TransitService

    var center = GeoPoint(lat: 53.3470, lon: -6.2570)
    var stops: [Stop] = []
    var favouriteStopIDs: Set<String> = ["oconnell", "tara"]
    var friends: [Friend] = SampleData.friends
    var plans: [Plan] = SampleData.plans
    var profile: GameProfile = SampleData.profile
    var challenges: [Challenge] = SampleData.challenges
    var shareMode: ShareMode = .precise
    var nextDeparture: (stop: Stop, arrival: Arrival)?
    var commute: Commute? { didSet { saveCommute() } }
    var commuteJourneys: [Journey] = []
    var commuteLoading = false
    var commuteError: String?

    init(transit: any TransitService = MockTransitService(), defaults: UserDefaults = .standard) {
        self.transit = transit
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.commuteKey) {
            commute = try? JSONDecoder().decode(Commute.self, from: data)
        }
    }

    private let defaults: UserDefaults
    private static let commuteKey = "commute.v1"

    /// The next departure you can still make for your commute (skipping cancelled ones).
    var nextCommuteJourney: Journey? { commuteJourneys.first { $0.status != .cancelled } }
    var commutePlanB: [Journey] {
        let next = nextCommuteJourney
        return Array(commuteJourneys.filter { $0 != next }.prefix(4))
    }

    /// Where "Get me there" starts: your commute's home stop if set, otherwise the map centre.
    var tripOrigin: GeoPoint { commute?.from.location ?? center }
    var tripOriginName: String { commute?.from.name ?? "city centre" }

    var livePlan: Plan? { plans.first(where: \.isLive) }
    var upcomingPlans: [Plan] { plans.filter { !$0.isLive }.sorted { $0.date < $1.date } }
    var favouriteStops: [Stop] { stops.filter { favouriteStopIDs.contains($0.id) } }

    var leaderboard: [(name: String, seed: Int, xp: Int, isMe: Bool)] {
        let me = (name: profile.name, seed: 99, xp: profile.xp, isMe: true)
        let others = friends.map { (name: $0.name, seed: $0.seed, xp: $0.level * 430 + $0.streak * 37, isMe: false) }
        return ([me] + others).sorted { $0.xp > $1.xp }
    }

    func load() async {
        stops = (try? await transit.nearbyStops(around: center)) ?? []
        let fav = favouriteStops.first ?? stops.first
        if let fav, let first = try? await transit.arrivals(for: fav).first {
            nextDeparture = (fav, first)
        }
        if commute == nil { await seedDemoCommute() }
        await refreshCommute()
    }

    func refreshCommute() async {
        guard let commute else { commuteJourneys = []; return }
        commuteLoading = true
        defer { commuteLoading = false }
        do {
            let all = try await transit.journeys(from: commute.from, to: commute.to, walkMinutes: commute.walkMinutes)
            commuteJourneys = all.filter { $0.status != .cancelled } + all.filter { $0.status == .cancelled }
            commuteError = nil
        } catch {
            commuteError = "Couldn't reach the transit server"
        }
    }

    func swapCommute() async {
        commute = commute?.reversed
        await refreshCommute()
    }

    /// Door-to-door trip for a plan; if nothing arrives on time, falls back to the earliest arrival.
    func trip(to plan: Plan) async throws -> TripPlan {
        let onTime = try await transit.trip(from: tripOrigin, to: plan.location, arriveBy: plan.date)
        if !onTime.options.isEmpty || plan.date.timeIntervalSinceNow > 3 * 3600 { return onTime }
        var asap = try await transit.trip(from: tripOrigin, to: plan.location, arriveBy: nil)
        asap.late = !asap.options.isEmpty
        return asap
    }

    private func seedDemoCommute() async {
        let (fromQuery, toQuery) = SampleData.demoCommute
        guard let from = try? await transit.searchStops(fromQuery).first,
              let to = try? await transit.searchStops(toQuery).first else { return }
        commute = Commute(from: from, to: to, walkMinutes: 5)
    }

    private func saveCommute() {
        if let commute, let data = try? JSONEncoder().encode(commute) {
            defaults.set(data, forKey: Self.commuteKey)
        } else {
            defaults.removeObject(forKey: Self.commuteKey)
        }
    }

    func toggleFavourite(_ stop: Stop) {
        if favouriteStopIDs.contains(stop.id) { favouriteStopIDs.remove(stop.id) } else { favouriteStopIDs.insert(stop.id) }
    }

    func vote(plan: Plan, option: TimeOption) {
        guard let p = plans.firstIndex(of: plan),
              let o = plans[p].timeOptions.firstIndex(where: { $0.id == option.id }) else { return }
        if plans[p].timeOptions[o].voterIDs.contains("me") {
            plans[p].timeOptions[o].voterIDs.remove("me")
        } else {
            plans[p].timeOptions[o].voterIDs.insert("me")
        }
    }

    func addPlan(_ plan: Plan) {
        plans.append(plan)
        profile.xp += 25
    }
}

enum SampleData {
    static let demoCommute = ("Ranelagh", "St Stephen's Green")

    static let friends: [Friend] = [
        Friend(id: "aoife", name: "Aoife Byrne", handle: "aoife", seed: 0, location: .init(lat: 53.3440, lon: -6.2672),
               status: .onTransit(mode: .luas, route: "Green", toward: "St Stephen's Green", etaMinutes: 4), level: 12, streak: 21),
        Friend(id: "cian", name: "Cian Murphy", handle: "cianm", seed: 1, location: .init(lat: 53.3498, lon: -6.2603),
               status: .at(place: "The Spire"), level: 9, streak: 6),
        Friend(id: "niamh", name: "Niamh Kelly", handle: "niamhk", seed: 2, location: .init(lat: 53.3388, lon: -6.2421),
               status: .onTransit(mode: .dart, route: "DART", toward: "Pearse", etaMinutes: 7), level: 15, streak: 40),
        Friend(id: "oisin", name: "Oisín Walsh", handle: "oisin", seed: 3, location: .init(lat: 53.3532, lon: -6.2689),
               status: .walking, level: 6, streak: 3),
        Friend(id: "saoirse", name: "Saoirse Doyle", handle: "saoirse", seed: 4, location: .init(lat: 53.3415, lon: -6.2530),
               status: .onTransit(mode: .bus, route: "46A", toward: "Dún Laoghaire", etaMinutes: 12), level: 11, streak: 14),
        Friend(id: "eoin", name: "Eoin Ryan", handle: "eoinr", seed: 5, location: .init(lat: 53.3460, lon: -6.2800),
               status: .offline, level: 4, streak: 0)
    ]

    static var plans: [Plan] {
        let f = friends
        let now = Date()
        return [
            Plan(id: "p1", title: "Pints at The Long Hall", symbol: "wineglass.fill", tint: Theme.ember,
                 date: now.addingTimeInterval(60 * 20), placeName: "The Long Hall, George's St",
                 location: .init(lat: 53.3425, lon: -6.2650),
                 attendees: [
                    .init(friend: f[0], rsvp: .going, etaMinutes: 4, arrived: false),
                    .init(friend: f[1], rsvp: .going, etaMinutes: nil, arrived: true),
                    .init(friend: f[2], rsvp: .going, etaMinutes: 11, arrived: false),
                    .init(friend: f[4], rsvp: .maybe, etaMinutes: 18, arrived: false)
                 ],
                 timeOptions: [.init(id: "t1", date: now.addingTimeInterval(60 * 20), voterIDs: ["aoife", "cian", "niamh", "me"])]),
            Plan(id: "p2", title: "Howth cliff walk", symbol: "figure.hiking", tint: Theme.accent,
                 date: now.addingTimeInterval(60 * 60 * 24 * 2), placeName: "Howth DART Station",
                 location: .init(lat: 53.3891, lon: -6.0739),
                 attendees: [
                    .init(friend: f[2], rsvp: .going, etaMinutes: nil, arrived: false),
                    .init(friend: f[3], rsvp: .invited, etaMinutes: nil, arrived: false),
                    .init(friend: f[4], rsvp: .going, etaMinutes: nil, arrived: false)
                 ],
                 timeOptions: [
                    .init(id: "t2", date: now.addingTimeInterval(60 * 60 * 24 * 2), voterIDs: ["niamh", "saoirse"]),
                    .init(id: "t3", date: now.addingTimeInterval(60 * 60 * 24 * 3), voterIDs: ["oisin"]),
                    .init(id: "t4", date: now.addingTimeInterval(60 * 60 * 24 * 3 + 3600 * 3), voterIDs: [])
                 ]),
            Plan(id: "p3", title: "Gig at Vicar St", symbol: "music.mic", tint: Theme.violet,
                 date: now.addingTimeInterval(60 * 60 * 24 * 6), placeName: "Vicar Street",
                 location: .init(lat: 53.3427, lon: -6.2783),
                 attendees: [
                    .init(friend: f[0], rsvp: .going, etaMinutes: nil, arrived: false),
                    .init(friend: f[5], rsvp: .maybe, etaMinutes: nil, arrived: false)
                 ],
                 timeOptions: [.init(id: "t5", date: now.addingTimeInterval(60 * 60 * 24 * 6), voterIDs: ["aoife"])])
        ]
    }

    static let profile = GameProfile(
        name: "Koushik Babu", handle: "koushik", xp: 4_320, streakDays: 17, tripsThisWeek: 11,
        totalTrips: 286, co2SavedKg: 142.6,
        badges: [
            Badge(id: "luas", title: "Luas Legend", symbol: "tram.fill", tint: TransitMode.luas.color, progress: 1),
            Badge(id: "dart", title: "Coastliner", symbol: "water.waves", tint: TransitMode.dart.color, progress: 0.72),
            Badge(id: "night", title: "Night Owl", symbol: "moon.stars.fill", tint: Theme.violet, progress: 1),
            Badge(id: "streak", title: "30-Day Streak", symbol: "flame.fill", tint: Theme.ember, progress: 17 / 30),
            Badge(id: "squad", title: "Squad Goals", symbol: "person.3.fill", tint: Theme.accent, progress: 0.4),
            Badge(id: "century", title: "Century", symbol: "100.circle.fill", tint: Theme.gold, progress: 1)
        ])

    static let challenges: [Challenge] = [
        Challenge(id: "c1", title: "Squad commute", detail: "Take 3 trips with friends", symbol: "person.2.fill",
                  rewardXP: 150, progress: 2, goal: 3),
        Challenge(id: "c2", title: "Explorer", detail: "Visit 5 new stops this week", symbol: "map.fill",
                  rewardXP: 200, progress: 3, goal: 5),
        Challenge(id: "c3", title: "Early bird", detail: "Board before 8am twice", symbol: "sunrise.fill",
                  rewardXP: 100, progress: 0, goal: 2)
    ]
}
