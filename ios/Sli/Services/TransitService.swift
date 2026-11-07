import Foundation

protocol TransitService: Sendable {
    /// Short attribution shown in the UI so users know where times come from.
    var sourceLabel: String { get }
    func nearbyStops(around point: GeoPoint) async throws -> [Stop]
    func arrivals(for stop: Stop) async throws -> [Arrival]
    func searchStops(_ query: String) async throws -> [Stop]
    func journeys(from: Stop, to: Stop, walkMinutes: Int) async throws -> [Journey]
    func trip(from: GeoPoint, to: GeoPoint, arriveBy: Date?) async throws -> TripPlan
}

struct MockTransitService: TransitService {
    var sourceLabel: String { "Sample data" }

    static let stops: [Stop] = [
        Stop(id: "oconnell", name: "O'Connell St Upper", code: "271", location: .init(lat: 53.3521, lon: -6.2605),
             modes: [.bus], routes: ["46A", "16", "13", "40", "123"]),
        Stop(id: "abbey", name: "Abbey Street", code: "LUAS-ABB", location: .init(lat: 53.3487, lon: -6.2580),
             modes: [.luas], routes: ["Red"]),
        Stop(id: "trinity", name: "Trinity", code: "LUAS-TRY", location: .init(lat: 53.3455, lon: -6.2590),
             modes: [.luas], routes: ["Green"]),
        Stop(id: "ssg", name: "St Stephen's Green", code: "LUAS-STS", location: .init(lat: 53.3394, lon: -6.2614),
             modes: [.luas, .bus], routes: ["Green", "11", "44"]),
        Stop(id: "tara", name: "Tara Street", code: "TARA", location: .init(lat: 53.3470, lon: -6.2545),
             modes: [.dart, .rail], routes: ["DART", "Northern Commuter"]),
        Stop(id: "connolly", name: "Connolly", code: "CNLLY", location: .init(lat: 53.3510, lon: -6.2498),
             modes: [.rail, .dart, .luas], routes: ["DART", "Enterprise", "Red"]),
        Stop(id: "pearse", name: "Pearse", code: "PERSE", location: .init(lat: 53.3434, lon: -6.2486),
             modes: [.dart], routes: ["DART"]),
        Stop(id: "gcd", name: "Grand Canal Dock", code: "GCDK", location: .init(lat: 53.3398, lon: -6.2378),
             modes: [.dart], routes: ["DART"])
    ]

    func nearbyStops(around point: GeoPoint) async throws -> [Stop] {
        Self.stops.sorted { distance($0.location, point) < distance($1.location, point) }
    }

    func searchStops(_ query: String) async throws -> [Stop] {
        Self.stops.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query) }
    }

    func arrivals(for stop: Stop) async throws -> [Arrival] {
        let headsigns: [TransitMode: [String]] = [
            .bus: ["Dún Laoghaire", "Ballymun", "Santry", "Charlestown", "Kilnamanagh"],
            .luas: ["Brides Glen", "Broombridge", "Tallaght", "The Point"],
            .dart: ["Greystones", "Howth", "Malahide", "Bray"],
            .rail: ["Maynooth", "Drogheda", "Belfast", "Dundalk"]
        ]
        var rng = SeededRandom(seed: stop.id.unicodeScalars.reduce(1469598103) { $0 &* 31 &+ UInt64($1.value) })
        return (0..<8).map { i in
            let mode = stop.modes[i % stop.modes.count]
            let route = mode == .bus ? stop.routes.filter { Int($0.prefix(2)) != nil }.randomElement(using: &rng) ?? "46A"
                : mode == .luas ? (stop.routes.first { $0 == "Red" || $0 == "Green" } ?? "Green")
                : mode == .dart ? "DART" : "Rail"
            let status: ArrivalStatus = i < 3 ? .live : i == 3 ? .unconfirmed : .scheduled
            return Arrival(id: "\(stop.id)-\(i)", route: route,
                           headsign: headsigns[mode]!.randomElement(using: &rng)!,
                           mode: mode, minutes: i * 4 + Int.random(in: 0...3, using: &rng), status: status)
        }
    }

    func journeys(from: Stop, to: Stop, walkMinutes: Int) async throws -> [Journey] {
        let now = Date()
        return try await arrivals(for: from).prefix(4).map { a in
            let departs = now.addingTimeInterval(Double(a.minutes) * 60)
            return Journey(id: a.id, route: a.route, mode: a.mode, headsign: a.headsign, fromStop: from.name,
                           fromCode: from.code, toStop: to.name, departs: departs,
                           arrives: departs.addingTimeInterval(12 * 60),
                           leaveAt: departs.addingTimeInterval(-Double(walkMinutes) * 60),
                           walkToMinutes: walkMinutes, status: a.status)
        }
    }

    func trip(from: GeoPoint, to: GeoPoint, arriveBy: Date?) async throws -> TripPlan {
        TripPlan(walkOnlyMinutes: 20, options: [])
    }

    private func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let dx = a.lat - b.lat, dy = a.lon - b.lon
        return dx * dx + dy * dy
    }
}

struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
