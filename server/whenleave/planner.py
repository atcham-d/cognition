"""Timetable queries: stop search, stop arrivals, A->B departures and door-to-door trips."""
import sqlite3
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from .ingest import haversine_m, normalise_name
from .realtime import TripRealtime

TZ = ZoneInfo("Europe/Dublin")
MISSED_GRACE_S = 60
UNCONFIRMED_WITHIN_S = 20 * 60  # vehicles this close should already be tracked
WALK_M_PER_MIN = 75  # ~4.5 km/h, with a detour factor applied to straight-line distance
WALK_DETOUR = 1.3
MAX_WALK_M = 900


def service_day_start(d: date) -> datetime:
    """GTFS times count from 'noon minus 12h', which differs from midnight on DST change days."""
    return datetime(d.year, d.month, d.day, 12, tzinfo=TZ) - timedelta(hours=12)


def active_services(conn: sqlite3.Connection, d: date) -> set[str]:
    ds = d.strftime("%Y%m%d")
    services = {r[0] for r in conn.execute(
        "SELECT service_id FROM calendar WHERE start_date<=? AND end_date>=? AND substr(days,?,1)='1'",
        (ds, ds, d.weekday() + 1))}
    for sid, ex in conn.execute("SELECT service_id, exception_type FROM calendar_dates WHERE date=?", (ds,)):
        if ex == 1:
            services.add(sid)
        elif ex == 2:
            services.discard(sid)
    return services


def walk_minutes(metres: float) -> int:
    return max(1, round(metres * WALK_DETOUR / WALK_M_PER_MIN))


# ---------------------------------------------------------------- stops

CLUSTER_SELECT = """SELECT c.cluster_id, c.name, c.lat, c.lon, c.modes,
    (SELECT group_concat(code, ' ') FROM stops s WHERE s.cluster_id = c.cluster_id),
    (SELECT group_concat(route, ' ') FROM (SELECT route FROM cluster_routes r
        WHERE r.cluster_id = c.cluster_id ORDER BY trips DESC LIMIT 12))
    FROM clusters c"""


def _cluster_row(row) -> dict:
    cid, name, lat, lon, modes, codes, routes = row
    modes_list = modes.split(",") if modes else []
    order = ["dart", "luas", "rail", "bus"]
    return {
        "id": cid, "name": name, "lat": lat, "lon": lon,
        "modes": sorted(modes_list, key=lambda m: order.index(m) if m in order else 9),
        # Luas/rail stop codes (99xxxx) are internal; bus pole numbers are what riders see
        "codes": [c for c in (codes or "").split(" ") if c and not c.startswith("99")],
        "routes": (routes or "").split(" ") if routes else [],
    }


def search_stops(conn: sqlite3.Connection, q: str, limit: int = 10) -> list[dict]:
    terms = normalise_name(q).split()
    if not terms:
        return []
    where = " AND ".join("(' ' || c.search || ' ') LIKE ?" for _ in terms)
    params = [f"% {t}%" for t in terms]
    rows = conn.execute(
        f"{CLUSTER_SELECT} WHERE {where} ORDER BY "
        "(' ' || c.search || ' ') LIKE ? DESC, "  # exact pole number / whole-word match
        "c.modes != 'bus' DESC, length(c.name) LIMIT ?",
        (*params, f"% {' '.join(terms)} %", limit)).fetchall()
    return [_cluster_row(r) for r in rows]


def nearby_stops(conn: sqlite3.Connection, lat: float, lon: float, limit: int = 8,
                 radius_m: float = 1000) -> list[dict]:
    d = radius_m / 111_000
    rows = conn.execute(f"{CLUSTER_SELECT} WHERE c.lat BETWEEN ? AND ? AND c.lon BETWEEN ? AND ?",
                        (lat - d, lat + d, lon - 1.7 * d, lon + 1.7 * d)).fetchall()
    out = [_cluster_row(r) | {"distance_m": round(haversine_m(lat, lon, r[2], r[3]))} for r in rows]
    out = [s for s in out if s["distance_m"] <= radius_m]
    return sorted(out, key=lambda s: s["distance_m"])[:limit]


def get_cluster(conn: sqlite3.Connection, cluster_id: int) -> dict | None:
    row = conn.execute(f"{CLUSTER_SELECT} WHERE c.cluster_id=?", (cluster_id,)).fetchone()
    return _cluster_row(row) if row else None


# ---------------------------------------------------------------- departures

def _status(live: bool, canceled: bool, realtime_on: bool, secs_away: float) -> str:
    """Plain-language reliability: never present a timetable time as if it were tracked."""
    if canceled:
        return "cancelled"
    if live:
        return "live"
    if realtime_on and secs_away <= UNCONFIRMED_WITHIN_S:
        return "unconfirmed"
    return "scheduled"


def _service_windows(conn, now: datetime, window_min: int, lookback_s: int = 15 * 60):
    for d in (now.date() - timedelta(days=1), now.date()):
        services = active_services(conn, d)
        if not services:
            continue
        base = service_day_start(d)
        rel = int((now - base).total_seconds())
        yield d, base, services, rel - lookback_s, rel + window_min * 60


def _apply_realtime(item: dict, rt: TripRealtime | None, now: datetime, realtime_on: bool,
                    has_arrival: bool) -> dict | None:
    if rt and rt.start_date and rt.start_date != item["service_date"].replace("-", ""):
        rt = None
    dep_delay = arr_delay = None
    skipped = False
    if rt:
        dep_delay, skipped = rt.delay_at(item["_o_seq"], item["_o_stop"])
        if has_arrival:
            arr_delay, _ = rt.delay_at(item["_d_seq"], item["_d_stop"], arrival=True)
    exp_dep = item["scheduled_dep"] + timedelta(seconds=dep_delay or 0)
    secs_away = (exp_dep - now).total_seconds()
    if secs_away < -MISSED_GRACE_S:
        return None
    live = rt is not None and dep_delay is not None
    canceled = bool(rt and (rt.canceled or skipped))
    out = {k: v for k, v in item.items() if not k.startswith("_")}
    out.update({
        "scheduled_dep": item["scheduled_dep"].isoformat(),
        "expected_dep": exp_dep.isoformat(),
        "minutes": max(0, int(secs_away // 60)),
        "delay_s": dep_delay,
        "live": live,
        "canceled": canceled,
        "status": _status(live, canceled, realtime_on, secs_away),
    })
    if has_arrival:
        exp_arr = item["scheduled_arr"] + timedelta(
            seconds=arr_delay if arr_delay is not None else dep_delay or 0)
        out["scheduled_arr"] = item["scheduled_arr"].isoformat()
        out["expected_arr"] = exp_arr.isoformat()
        out["_exp_dep"], out["_exp_arr"] = exp_dep, exp_arr
    else:
        out["_exp_dep"] = exp_dep
    return out


def _strip(rows: list[dict]) -> list[dict]:
    return [{k: v for k, v in r.items() if not k.startswith("_")} for r in rows]


ARRIVALS_SQL = """
SELECT o.trip_id, o.seq, o.dep, o.stop_id, r.short_name, r.mode, t.headsign
FROM stop_times o
JOIN trips t ON t.trip_id = o.trip_id
JOIN routes r ON r.route_id = t.route_id
WHERE o.stop_id IN (SELECT stop_id FROM stops WHERE cluster_id = ?)
  AND o.dep BETWEEN ? AND ? AND o.pickup != 1
  AND t.service_id IN ({services})
"""


def stop_arrivals(conn: sqlite3.Connection, cluster_id: int, now: datetime, window_min: int = 90,
                  limit: int = 12, realtime: dict[str, TripRealtime] | None = None) -> list[dict]:
    """Next departures from any platform/pole in a stop cluster."""
    now = now.astimezone(TZ)
    seen, results = set(), []
    for d, base, services, lo, hi in _service_windows(conn, now, window_min):
        sql = ARRIVALS_SQL.format(services=",".join("?" * len(services)))
        for trip_id, seq, dep, stop_id, route, mode, headsign in conn.execute(
                sql, (cluster_id, lo, hi, *services)):
            if (trip_id, d) in seen:
                continue
            seen.add((trip_id, d))
            item = {"trip_id": trip_id, "service_date": d.isoformat(), "route": route, "mode": mode,
                    "headsign": headsign, "_o_seq": seq, "_o_stop": stop_id,
                    "scheduled_dep": base + timedelta(seconds=dep)}
            row = _apply_realtime(item, (realtime or {}).get(trip_id), now, realtime is not None, False)
            if row:
                results.append(row)
    results.sort(key=lambda r: r["_exp_dep"])
    return _strip(results[:limit])


DEPARTURES_SQL = """
SELECT o.trip_id, o.seq, o.dep, o.stop_id, d.seq, MIN(d.arr), d.stop_id,
       r.short_name, r.mode, t.headsign, os.name, os.code, ds.name, os.cluster_id, ds.cluster_id
FROM stop_times o
JOIN stop_times d ON d.trip_id = o.trip_id AND d.seq > o.seq
JOIN trips t ON t.trip_id = o.trip_id
JOIN routes r ON r.route_id = t.route_id
JOIN stops os ON os.stop_id = o.stop_id
JOIN stops ds ON ds.stop_id = d.stop_id
WHERE os.cluster_id IN ({origins}) AND ds.cluster_id IN ({dests})
  AND os.cluster_id != ds.cluster_id
  AND o.dep BETWEEN ? AND ?
  AND o.pickup != 1 AND d.dropoff != 1
  AND t.service_id IN ({services})
GROUP BY o.trip_id, o.seq, ds.cluster_id
"""


def _direct(conn, from_ids: list[int], to_ids: list[int], now: datetime, window_min: int,
            realtime: dict[str, TripRealtime] | None) -> list[dict]:
    """Direct (single-vehicle) trips from any origin cluster to any destination cluster."""
    candidates: dict[tuple, dict] = {}
    for d, base, services, lo, hi in _service_windows(conn, now, window_min):
        sql = DEPARTURES_SQL.format(origins=",".join("?" * len(from_ids)), dests=",".join("?" * len(to_ids)),
                                    services=",".join("?" * len(services)))
        for row in conn.execute(sql, (*from_ids, *to_ids, lo, hi, *services)):
            (trip_id, o_seq, dep, o_stop, d_seq, arr, d_stop,
             route, mode, headsign, o_name, o_code, d_name, o_cluster, d_cluster) = row
            key = (trip_id, d, o_cluster, d_cluster)
            # loops can visit the origin twice; keep the boarding closest to the destination
            if key in candidates and candidates[key]["_o_seq"] > o_seq:
                continue
            candidates[key] = {
                "trip_id": trip_id, "service_date": d.isoformat(), "route": route, "mode": mode,
                "headsign": headsign, "from_stop": o_name,
                "from_code": "" if (o_code or "").startswith("99") else o_code, "to_stop": d_name,
                "_o_seq": o_seq, "_d_seq": d_seq, "_o_stop": o_stop, "_d_stop": d_stop,
                "_o_cluster": o_cluster, "_d_cluster": d_cluster,
                "scheduled_dep": base + timedelta(seconds=dep),
                "scheduled_arr": base + timedelta(seconds=arr),
            }
    out = []
    for item in candidates.values():
        row = _apply_realtime(item, (realtime or {}).get(item["trip_id"]), now, realtime is not None, True)
        if row:
            row["_o_cluster"], row["_d_cluster"] = item["_o_cluster"], item["_d_cluster"]
            out.append(row)
    out.sort(key=lambda r: r["_exp_dep"])
    return out


def departures(conn: sqlite3.Connection, from_id: int, to_id: int, now: datetime,
               walk_min: int = 0, window_min: int = 120, limit: int = 10,
               realtime: dict[str, TripRealtime] | None = None) -> list[dict]:
    """Direct trips between two stop clusters, with 'leave in' accounting for the walk to the stop."""
    now = now.astimezone(TZ)
    rows = _direct(conn, [from_id], [to_id], now, window_min, realtime)
    for r in rows:
        leave_at = r["_exp_dep"] - timedelta(minutes=walk_min)
        r["leave_at"] = leave_at.isoformat()
        r["leave_in_s"] = int((leave_at - now).total_seconds())
        r["duration_min"] = round((r["_exp_arr"] - r["_exp_dep"]).total_seconds() / 60)
    return _strip(rows[:limit])


def plan_trip(conn: sqlite3.Connection, from_lat: float, from_lon: float, to_lat: float, to_lon: float,
              now: datetime, arrive_by: datetime | None = None,
              realtime: dict[str, TripRealtime] | None = None, options: int = 3) -> dict:
    """Door-to-door direct trip: walk -> one vehicle -> walk. Returns best options by leave time."""
    now = now.astimezone(TZ)
    origins = nearby_stops(conn, from_lat, from_lon, limit=40, radius_m=MAX_WALK_M)
    dests = nearby_stops(conn, to_lat, to_lon, limit=40, radius_m=MAX_WALK_M)
    direct_walk = walk_minutes(haversine_m(from_lat, from_lon, to_lat, to_lon))
    query_now, window = now, 120
    if arrive_by:
        arrive_by = arrive_by.astimezone(TZ)
        query_now = max(now, arrive_by - timedelta(hours=2))
        window = max(10, int((arrive_by - query_now).total_seconds() // 60))
    rt = realtime if query_now - now < timedelta(hours=1) else None

    trips: dict[tuple[str, str], dict] = {}
    walk_to = {o["id"]: walk_minutes(o["distance_m"]) for o in origins}
    walk_from = {d["id"]: walk_minutes(d["distance_m"]) for d in dests}
    rows = _direct(conn, list(walk_to), list(walk_from), query_now, window, rt) if origins and dests else []
    for r in rows:
        wt, wf = walk_to[r["_o_cluster"]], walk_from[r["_d_cluster"]]
        leave_at = r["_exp_dep"] - timedelta(minutes=wt)
        arrive_at = r["_exp_arr"] + timedelta(minutes=wf)
        if leave_at < now - timedelta(seconds=MISSED_GRACE_S):
            continue
        if arrive_by and arrive_at > arrive_by:
            continue
        opt = {**r, "walk_to_min": wt, "walk_from_min": wf,
               "from_stop_id": r["_o_cluster"], "to_stop_id": r["_d_cluster"],
               "_leave": leave_at, "_arrive": arrive_at,
               "leave_at": leave_at.isoformat(), "arrive_at": arrive_at.isoformat(),
               "leave_in_s": int((leave_at - now).total_seconds()),
               "total_min": round((arrive_at - leave_at).total_seconds() / 60)}
        key = (r["trip_id"], r["service_date"])
        best = trips.get(key)
        # same vehicle reachable from several stops: keep the earliest arrival, then the latest leave
        if not best or (arrive_at, -leave_at.timestamp()) < (best["_arrive"], -best["_leave"].timestamp()):
            trips[key] = opt

    ranked = list(trips.values())
    if arrive_by:
        ranked.sort(key=lambda t: (t["status"] == "cancelled", -t["_leave"].timestamp()))
    else:
        ranked.sort(key=lambda t: (t["status"] == "cancelled", t["_arrive"]))
    picked, seen_dep = [], set()
    for t in ranked:
        if (t["route"], t["_leave"]) in seen_dep:
            continue
        seen_dep.add((t["route"], t["_leave"]))
        picked.append(t)
        if len(picked) == options:
            break
    if not arrive_by:
        picked.sort(key=lambda t: t["_leave"])
    return {"walk_only_min": direct_walk, "options": _strip(picked)}
