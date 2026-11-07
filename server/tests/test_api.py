from datetime import datetime

from fastapi.testclient import TestClient

from whenleave import planner
from whenleave.app import create_app
from whenleave.realtime import RealtimeFeed

NOW = datetime(2026, 11, 9, 7, 55, tzinfo=planner.TZ)


def client(db_path, payload=None):
    feed = RealtimeFeed(None, fetcher=(lambda: payload)) if payload is not None else RealtimeFeed(None)
    return TestClient(create_app(str(db_path), feed=feed, clock=lambda: NOW))


def test_endpoints_end_to_end(db_path):
    with client(db_path) as c:
        assert c.get("/api/health").json() == {"ok": True, "realtime": False}
        stops = c.get("/api/stops/search", params={"q": "main"}).json()
        main = stops[0]["id"]
        market = c.get("/api/stops/search", params={"q": "2001"}).json()[0]["id"]
        near = c.get("/api/stops/near", params={"lat": 53.3001, "lon": -6.2001}).json()
        assert near[0]["id"] == main and near[0]["distance_m"] < 50

        arr = c.get(f"/api/stops/{market}/arrivals").json()
        assert arr["realtime"] is False and arr["arrivals"][0]["route"] == "DART"

        deps = c.get("/api/departures", params={"from": main, "to": market, "walk": 3}).json()
        assert deps["departures"][0]["leave_in_s"] == 120

        trip = c.get("/api/trip", params={"from_lat": 53.2995, "from_lon": -6.2, "to_lat": 53.3105,
                                          "to_lon": -6.2, "arrive_by": "2026-11-09T08:20:00"}).json()
        assert trip["options"][0]["route"] == "46A"

        assert c.get("/api/stops/99999/arrivals").status_code == 404


def test_realtime_feed_failure_falls_back_to_schedule(db_path):
    def boom():
        raise RuntimeError("NTA down")
    with TestClient(create_app(str(db_path), feed=RealtimeFeed(None, fetcher=boom), clock=lambda: NOW)) as c:
        market = c.get("/api/stops/search", params={"q": "market"}).json()[0]["id"]
        body = c.get(f"/api/stops/{market}/arrivals").json()
        assert body["realtime"] is False
        assert body["arrivals"][0]["status"] == "scheduled"
