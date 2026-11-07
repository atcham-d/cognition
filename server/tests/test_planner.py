from datetime import datetime

from whenleave import planner
from whenleave.realtime import parse_trip_updates

TZ = planner.TZ
MON_0755 = datetime(2026, 11, 9, 7, 55, tzinfo=TZ)


def cluster(conn, name):
    return planner.search_stops(conn, name)[0]["id"]


def test_same_name_stops_across_road_are_one_cluster_but_distant_ones_are_not(conn):
    near = conn.execute("SELECT cluster_id FROM stops WHERE stop_id IN ('A1','A2')").fetchall()
    far = conn.execute("SELECT cluster_id FROM stops WHERE stop_id='M1'").fetchone()
    assert near[0] == near[1]
    assert far != near[0]


def test_search_by_name_and_pole_number(conn):
    by_name = planner.search_stops(conn, "market")
    assert by_name[0]["name"] == "Market Sq"
    assert by_name[0]["routes"][:2] == ["46A", "DART"] or set(by_name[0]["routes"]) == {"46A", "DART"}
    assert planner.search_stops(conn, "1235")[0]["name"] == "Main St"
    assert "999001" not in planner.search_stops(conn, "seaside")[0]["codes"]


def test_departures_respect_direction_and_walk_time(conn):
    a, b = cluster(conn, "1234"), cluster(conn, "market")
    out = planner.departures(conn, a, b, MON_0755, walk_min=3)
    assert [d["trip_id"] for d in out] == ["T1"]
    assert out[0]["leave_in_s"] == 2 * 60
    assert out[0]["status"] == "scheduled"
    assert [d["trip_id"] for d in planner.departures(conn, b, a, MON_0755)] == ["T2"]


def test_after_midnight_trip_belongs_to_previous_service_day(conn):
    a, b = cluster(conn, "1234"), cluster(conn, "market")
    out = planner.departures(conn, a, b, datetime(2026, 11, 10, 0, 20, tzinfo=TZ))
    assert [(d["trip_id"], d["service_date"]) for d in out] == [("T3", "2026-11-09")]
    assert out[0]["expected_dep"].startswith("2026-11-10T00:30")


def test_calendar_exception_removes_service(conn):
    a, b = cluster(conn, "1234"), cluster(conn, "market")
    assert planner.departures(conn, a, b, datetime(2026, 12, 25, 7, 55, tzinfo=TZ)) == []


def test_realtime_delay_cancellation_and_unconfirmed(conn):
    a, b = cluster(conn, "1234"), cluster(conn, "market")
    delayed = parse_trip_updates({"entity": [{"trip_update": {
        "trip": {"trip_id": "T1", "start_date": "20261109"},
        "stop_time_update": [{"stop_sequence": 1, "departure": {"delay": 120}}]}}]})
    d = planner.departures(conn, a, b, MON_0755, realtime=delayed)[0]
    assert d["status"] == "live" and d["expected_dep"].startswith("2026-11-09T08:02")
    assert d["expected_arr"].startswith("2026-11-09T08:12")

    cancelled = parse_trip_updates({"entity": [{"tripUpdate": {
        "trip": {"tripId": "T1", "scheduleRelationship": "CANCELED"}}}]})
    assert planner.departures(conn, a, b, MON_0755, realtime=cancelled)[0]["status"] == "cancelled"

    # feed is up but this vehicle, due in 5 minutes, isn't being tracked: likely ghost
    assert planner.departures(conn, a, b, MON_0755, realtime={})[0]["status"] == "unconfirmed"


def test_realtime_for_other_service_day_is_ignored(conn):
    a, b = cluster(conn, "1234"), cluster(conn, "market")
    rt = parse_trip_updates({"entity": [{"trip_update": {
        "trip": {"trip_id": "T1", "start_date": "20261108"},
        "stop_time_update": [{"stop_sequence": 1, "departure": {"delay": 600}}]}}]})
    assert planner.departures(conn, a, b, MON_0755, realtime=rt)[0]["delay_s"] is None


def test_stop_arrivals_list_all_routes_from_cluster(conn):
    out = planner.stop_arrivals(conn, cluster(conn, "market"), MON_0755)
    assert [(x["route"], x["minutes"]) for x in out] == [("DART", 10), ("46A", 35)]


def test_plan_trip_arrive_by_picks_latest_departure_that_makes_it(conn):
    res = planner.plan_trip(conn, 53.2995, -6.2000, 53.3105, -6.2000, MON_0755,
                            arrive_by=datetime(2026, 11, 9, 8, 20, tzinfo=TZ))
    opt = res["options"][0]
    assert opt["trip_id"] == "T1"
    assert opt["walk_to_min"] >= 1 and opt["walk_from_min"] >= 1
    assert opt["leave_at"] < opt["scheduled_dep"] < opt["arrive_at"]
    too_early = planner.plan_trip(conn, 53.2995, -6.2000, 53.3105, -6.2000, MON_0755,
                                  arrive_by=datetime(2026, 11, 9, 8, 5, tzinfo=TZ))
    assert too_early["options"] == []
