import SwiftUI
import CoreLocation

enum TransitMode: String, Codable, CaseIterable, Sendable {
    case bus, luas, dart, rail

    var symbol: String {
        switch self {
        case .bus: "bus.fill"
        case .luas: "tram.fill"
        case .dart: "lightrail.fill"
        case .rail: "train.side.front.car"
        }
    }

    var title: String {
        switch self {
        case .bus: "Bus"
        case .luas: "Luas"
        case .dart: "DART"
        case .rail: "Rail"
        }
    }

    var color: Color {
        switch self {
        case .bus: Color(red: 1.0, green: 0.80, blue: 0.10)
        case .luas: Color(red: 0.55, green: 0.20, blue: 0.62)
        case .dart: Color(red: 0.38, green: 0.74, blue: 0.27)
        case .rail: Color(red: 0.0, green: 0.55, blue: 0.48)
        }
    }

    var foreground: Color { self == .bus ? .black : .white }
}

struct GeoPoint: Codable, Hashable, Sendable {
    var lat: Double
    var lon: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct Stop: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let code: String
    let location: GeoPoint
    let modes: [TransitMode]
    let routes: [String]
    var primaryMode: TransitMode { modes.first ?? .bus }
}

struct Arrival: Identifiable, Hashable, Sendable {
    let id: String
    let route: String
    let headsign: String
    let mode: TransitMode
    var minutes: Int
    let isLive: Bool
    var crowding: Double
}

enum FriendStatus: Hashable, Sendable {
    case onTransit(mode: TransitMode, route: String, toward: String, etaMinutes: Int)
    case at(place: String)
    case walking
    case offline

    var label: String {
        switch self {
        case let .onTransit(_, route, toward, eta): "On the \(route) → \(toward) · \(eta) min"
        case let .at(place): "At \(place)"
        case .walking: "Walking"
        case .offline: "Sharing paused"
        }
    }
}

enum ShareMode: String, CaseIterable, Identifiable, Sendable {
    case precise, approximate, paused
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .precise: "location.fill"
        case .approximate: "location.circle"
        case .paused: "location.slash.fill"
        }
    }
}

struct Friend: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let handle: String
    let seed: Int
    var location: GeoPoint
    var status: FriendStatus
    var level: Int
    var streak: Int

    var ringColor: Color? {
        if case let .onTransit(mode, _, _, _) = status { return mode.color }
        return nil
    }
}

enum RSVP: String, Sendable { case going, maybe, invited }

struct PlanAttendee: Identifiable, Hashable, Sendable {
    var id: String { friend.id }
    let friend: Friend
    var rsvp: RSVP
    var etaMinutes: Int?
    var arrived: Bool
}

struct TimeOption: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    var voterIDs: Set<String>
}

struct Plan: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var symbol: String
    var tint: Color
    var date: Date
    var placeName: String
    var location: GeoPoint
    var attendees: [PlanAttendee]
    var timeOptions: [TimeOption]
    var isLive: Bool { abs(date.timeIntervalSinceNow) < 60 * 90 }
}

struct Badge: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    var progress: Double
}

struct GameProfile: Sendable {
    var name: String
    var handle: String
    var xp: Int
    var streakDays: Int
    var tripsThisWeek: Int
    var totalTrips: Int
    var co2SavedKg: Double
    var badges: [Badge]

    static let xpPerLevel = 500
    var level: Int { xp / Self.xpPerLevel + 1 }
    var levelProgress: Double { Double(xp % Self.xpPerLevel) / Double(Self.xpPerLevel) }
    var xpToNext: Int { Self.xpPerLevel - xp % Self.xpPerLevel }
}

struct Challenge: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let rewardXP: Int
    var progress: Int
    let goal: Int
}
