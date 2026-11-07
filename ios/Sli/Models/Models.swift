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

struct Stop: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let code: String
    let location: GeoPoint
    let modes: [TransitMode]
    let routes: [String]
    var primaryMode: TransitMode { modes.first ?? .bus }
}

/// How much to trust a departure time. Never present a timetable time as if it were tracked.
enum ArrivalStatus: String, Codable, Sendable {
    /// Vehicle is reporting its position; time includes delay.
    case live
    /// Due soon but not reporting: the classic "ghost bus" risk.
    case unconfirmed
    /// Timetable only (too far out to be tracked yet, or live feed unavailable).
    case scheduled
    case cancelled

    var title: String {
        switch self {
        case .live: "Live"
        case .unconfirmed: "Unconfirmed"
        case .scheduled: "Timetable"
        case .cancelled: "Cancelled"
        }
    }

    var explanation: String {
        switch self {
        case .live: "Tracked right now"
        case .unconfirmed: "Not tracked yet, may not run"
        case .scheduled: "Timetable time, not tracked"
        case .cancelled: "Operator cancelled this one"
        }
    }

    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .unconfirmed: "questionmark.circle.fill"
        case .scheduled: "calendar"
        case .cancelled: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .live: Theme.accent
        case .unconfirmed: Theme.gold
        case .scheduled: .secondary
        case .cancelled: Theme.ember
        }
    }
}

struct Arrival: Identifiable, Hashable, Sendable {
    let id: String
    let route: String
    let headsign: String
    let mode: TransitMode
    var minutes: Int
    var status: ArrivalStatus = .scheduled
    var delayMinutes: Int? = nil
    /// nil when there is no occupancy data (the NTA feed doesn't provide it for Dublin today).
    var crowding: Double? = nil
    var isLive: Bool { status == .live }
}

/// One way to get from A to B on a single vehicle, including the walks either side.
struct Journey: Identifiable, Hashable, Sendable {
    let id: String
    let route: String
    let mode: TransitMode
    let headsign: String
    let fromStop: String
    let fromCode: String
    let toStop: String
    let departs: Date
    let arrives: Date
    let leaveAt: Date
    var walkToMinutes: Int
    var walkFromMinutes: Int = 0
    var status: ArrivalStatus
    var delayMinutes: Int? = nil

    var arriveAtDoor: Date { arrives.addingTimeInterval(Double(walkFromMinutes) * 60) }
}

struct TripPlan: Sendable {
    var walkOnlyMinutes: Int
    var options: [Journey]
    /// True when nothing gets you there by the requested time and these are the earliest arrivals instead.
    var late = false
}

struct Commute: Codable, Hashable, Sendable {
    var from: Stop
    var to: Stop
    var walkMinutes: Int

    var reversed: Commute { Commute(from: to, to: from, walkMinutes: walkMinutes) }
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
