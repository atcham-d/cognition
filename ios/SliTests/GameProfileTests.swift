import Testing
@testable import Sli

struct GameProfileTests {
    @Test func levelMath() {
        var p = SampleData.profile
        p.xp = 1_250
        #expect(p.level == 3)
        #expect(p.xpToNext == 250)
        #expect(abs(p.levelProgress - 0.5) < 0.0001)
    }

    @Test func nearbyStopsSortedByDistance() async throws {
        let stops = try await MockTransitService().nearbyStops(around: .init(lat: 53.3398, lon: -6.2378))
        #expect(stops.first?.id == "gcd")
    }
}
