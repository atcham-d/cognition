import Foundation

/// Talks to the Slí transit server (`server/`), which serves TFI GTFS timetables
/// merged with NTA GTFS-Realtime delays and cancellations.
struct LiveTransitService: TransitService {
    let baseURL: URL
    var session: URLSession = .shared

    var sourceLabel: String { "TFI timetable + NTA live" }

    static let defaultURL = URL(string: "http://127.0.0.1:8000")!

    /// Reads `TransitAPIURL` from Info.plist; pass `-mockTransit YES` to use sample data instead.
    static func fromBundle(_ bundle: Bundle = .main) -> LiveTransitService? {
        if UserDefaults.standard.bool(forKey: "mockTransit") { return nil }
        let raw = (bundle.object(forInfoDictionaryKey: "TransitAPIURL") as? String) ?? ""
        let url = raw.hasPrefix("http") ? URL(string: raw) : nil
        return LiveTransitService(baseURL: url ?? defaultURL)
    }

    func nearbyStops(around point: GeoPoint) async throws -> [Stop] {
        let dto: [StopDTO] = try await get("/api/stops/near", ["lat": "\(point.lat)", "lon": "\(point.lon)", "limit": "12"])
        return dto.map(\.stop)
    }

    func searchStops(_ query: String) async throws -> [Stop] {
        let dto: [StopDTO] = try await get("/api/stops/search", ["q": query])
        return dto.map(\.stop)
    }

    func arrivals(for stop: Stop) async throws -> [Arrival] {
        let dto: ArrivalsResponse = try await get("/api/stops/\(stop.id)/arrivals", [:])
        return dto.arrivals.map(\.arrival)
    }

    func journeys(from: Stop, to: Stop, walkMinutes: Int) async throws -> [Journey] {
        let dto: DeparturesResponse = try await get("/api/departures",
                                                    ["from": from.id, "to": to.id, "walk": "\(walkMinutes)"])
        return dto.departures.compactMap { $0.journey(walkTo: walkMinutes, walkFrom: 0) }
    }

    func trip(from: GeoPoint, to: GeoPoint, arriveBy: Date?) async throws -> TripPlan {
        var query = ["from_lat": "\(from.lat)", "from_lon": "\(from.lon)", "to_lat": "\(to.lat)", "to_lon": "\(to.lon)"]
        if let arriveBy { query["arrive_by"] = arriveBy.formatted(.iso8601) }
        let dto: TripResponse = try await get("/api/trip", query)
        return TripPlan(walkOnlyMinutes: dto.walkOnlyMin,
                        options: dto.options.compactMap { $0.journey(walkTo: $0.walkToMin ?? 0, walkFrom: $0.walkFromMin ?? 0) })
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    static func parseDate(_ s: String) -> Date? {
        if let d = try? Date(s, strategy: .iso8601) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

// MARK: - Wire format

struct StopDTO: Decodable {
    let id: Int
    let name: String
    let lat: Double
    let lon: Double
    let modes: [String]
    let codes: [String]
    let routes: [String]

    var stop: Stop {
        let parsed = modes.compactMap(TransitMode.init(rawValue:))
        return Stop(id: String(id), name: name, code: codes.first ?? "", location: .init(lat: lat, lon: lon),
                    modes: parsed.isEmpty ? [.bus] : parsed, routes: routes)
    }
}

struct ArrivalDTO: Decodable {
    let tripId: String
    let serviceDate: String
    let route: String
    let mode: String
    let headsign: String
    let minutes: Int
    let status: String
    let delayS: Int?

    var arrival: Arrival {
        Arrival(id: "\(tripId)-\(serviceDate)", route: route, headsign: headsign,
                mode: TransitMode(rawValue: mode) ?? .bus, minutes: minutes,
                status: ArrivalStatus(rawValue: status) ?? .scheduled,
                delayMinutes: delayS.map { Int((Double($0) / 60).rounded()) })
    }
}

struct ArrivalsResponse: Decodable {
    let realtime: Bool
    let arrivals: [ArrivalDTO]
}

struct JourneyDTO: Decodable {
    let tripId: String
    let serviceDate: String
    let route: String
    let mode: String
    let headsign: String
    let fromStop: String
    let fromCode: String?
    let toStop: String
    let expectedDep: String
    let expectedArr: String
    let leaveAt: String
    let status: String
    let delayS: Int?
    let walkToMin: Int?
    let walkFromMin: Int?

    func journey(walkTo: Int, walkFrom: Int) -> Journey? {
        guard let dep = LiveTransitService.parseDate(expectedDep),
              let arr = LiveTransitService.parseDate(expectedArr),
              let leave = LiveTransitService.parseDate(leaveAt) else { return nil }
        return Journey(id: "\(tripId)-\(serviceDate)", route: route, mode: TransitMode(rawValue: mode) ?? .bus,
                       headsign: headsign, fromStop: fromStop, fromCode: fromCode ?? "", toStop: toStop,
                       departs: dep, arrives: arr, leaveAt: leave, walkToMinutes: walkTo, walkFromMinutes: walkFrom,
                       status: ArrivalStatus(rawValue: status) ?? .scheduled,
                       delayMinutes: delayS.map { Int((Double($0) / 60).rounded()) })
    }
}

struct DeparturesResponse: Decodable {
    let realtime: Bool
    let departures: [JourneyDTO]
}

struct TripResponse: Decodable {
    let realtime: Bool
    let walkOnlyMin: Int
    let options: [JourneyDTO]
}
