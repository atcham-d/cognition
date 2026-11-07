import Foundation
import Testing
@testable import Sli

struct TransitTests {
    @Test func decodesServerArrivals() throws {
        let json = """
        {"now":"2026-11-09T07:55:00+00:00","realtime":true,"stop":{},"arrivals":[
          {"trip_id":"T1","service_date":"2026-11-09","route":"46A","mode":"bus","headsign":"Dún Laoghaire",
           "scheduled_dep":"2026-11-09T08:00:00+00:00","expected_dep":"2026-11-09T08:02:00+00:00",
           "minutes":7,"delay_s":120,"live":true,"canceled":false,"status":"live"},
          {"trip_id":"T2","service_date":"2026-11-09","route":"Green","mode":"luas","headsign":"Parnell",
           "scheduled_dep":"2026-11-09T08:01:00+00:00","expected_dep":"2026-11-09T08:01:00+00:00",
           "minutes":6,"delay_s":null,"live":false,"canceled":false,"status":"unconfirmed"}]}
        """
        let res = try LiveTransitService.decoder.decode(ArrivalsResponse.self, from: Data(json.utf8))
        let arrivals = res.arrivals.map(\.arrival)
        #expect(arrivals[0].status == .live && arrivals[0].delayMinutes == 2 && arrivals[0].isLive)
        #expect(arrivals[1].status == .unconfirmed && arrivals[1].mode == .luas && arrivals[1].crowding == nil)
    }

    @Test func decodesTripOptions() throws {
        let json = """
        {"now":"2026-11-09T07:55:00+00:00","realtime":false,"walk_only_min":33,"options":[
          {"trip_id":"T1","service_date":"2026-11-09","route":"Green","mode":"luas","headsign":"Parnell",
           "from_stop":"Ranelagh","from_code":"","to_stop":"St. Stephen's Green",
           "scheduled_dep":"2026-11-09T08:00:00+00:00","expected_dep":"2026-11-09T08:00:00+00:00",
           "scheduled_arr":"2026-11-09T08:06:00+00:00","expected_arr":"2026-11-09T08:06:00+00:00",
           "minutes":5,"delay_s":null,"live":false,"canceled":false,"status":"scheduled",
           "walk_to_min":3,"walk_from_min":8,"from_stop_id":109,"to_stop_id":2705,
           "leave_at":"2026-11-09T07:57:00+00:00","arrive_at":"2026-11-09T08:14:00+00:00",
           "leave_in_s":120,"total_min":17}]}
        """
        let res = try LiveTransitService.decoder.decode(TripResponse.self, from: Data(json.utf8))
        let j = try #require(res.options.first?.journey(walkTo: 3, walkFrom: 8))
        #expect(res.walkOnlyMin == 33)
        #expect(j.leaveAt.addingTimeInterval(180) == j.departs)
        #expect(j.arriveAtDoor.timeIntervalSince(j.arrives) == 8 * 60)
    }

    @Test func stopIDsAndModesMapFromServer() throws {
        let json = #"[{"id":109,"name":"Ranelagh","lat":53.3,"lon":-6.25,"modes":["luas","bus"],"codes":["851"],"routes":["Green","11"]}]"#
        let stops = try LiveTransitService.decoder.decode([StopDTO].self, from: Data(json.utf8)).map(\.stop)
        #expect(stops[0].id == "109" && stops[0].modes == [.luas, .bus] && stops[0].code == "851")
    }

    @Test func leaveInWording() {
        #expect(LeaveIn.headline(10 * 60) == "Leave in 10 min")
        #expect(LeaveIn.headline(20) == "Leave now")
        #expect(LeaveIn.headline(-90) == "Run!")
    }

    @MainActor @Test func commutePersistsAndSwaps() async throws {
        let defaults = try #require(UserDefaults(suiteName: "TransitTests"))
        defaults.removePersistentDomain(forName: "TransitTests")
        let state = AppState(defaults: defaults)
        let stops = MockTransitService.stops
        state.commute = Commute(from: stops[0], to: stops[4], walkMinutes: 4)
        #expect(AppState(defaults: defaults).commute?.to.id == stops[4].id)
        await state.swapCommute()
        #expect(state.commute?.from.id == stops[4].id)
        #expect(!state.commuteJourneys.isEmpty)
    }
}
