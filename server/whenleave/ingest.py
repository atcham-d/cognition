"""Build a compact SQLite timetable from TFI GTFS feeds.

Usage: python -m whenleave.ingest [--src DIR_WITH_ZIPS] [--db data/gtfs.db]
"""
import argparse
import csv
import io
import math
import re
import sqlite3
import urllib.request
import zipfile
from pathlib import Path

FEED_BASE = "https://www.transportforireland.ie/transitData/Data/"
FEEDS = {
    "bus": "GTFS_Dublin_Bus.zip",
    "luas": "GTFS_LUAS.zip",
    "rail": "GTFS_Irish_Rail.zip",
}
CLUSTER_RADIUS_M = 350

SCHEMA = """
CREATE TABLE routes (route_id TEXT PRIMARY KEY, short_name TEXT, long_name TEXT, route_type INTEGER, mode TEXT);
CREATE TABLE trips (trip_id TEXT PRIMARY KEY, route_id TEXT, service_id TEXT, headsign TEXT);
CREATE TABLE stops (stop_id TEXT PRIMARY KEY, code TEXT, name TEXT, lat REAL, lon REAL, mode TEXT, cluster_id INTEGER);
CREATE TABLE clusters (cluster_id INTEGER PRIMARY KEY, name TEXT, lat REAL, lon REAL, modes TEXT, search TEXT);
CREATE TABLE stop_times (trip_id TEXT, stop_id TEXT, seq INTEGER, arr INTEGER, dep INTEGER, pickup INTEGER, dropoff INTEGER);
CREATE TABLE calendar (service_id TEXT PRIMARY KEY, days TEXT, start_date TEXT, end_date TEXT);
CREATE TABLE calendar_dates (service_id TEXT, date TEXT, exception_type INTEGER);
CREATE TABLE cluster_routes (cluster_id INTEGER, route TEXT, mode TEXT, trips INTEGER);
"""

INDEXES = """
CREATE INDEX st_stop_dep ON stop_times(stop_id, dep);
CREATE INDEX st_trip_seq ON stop_times(trip_id, seq);
CREATE INDEX stops_cluster ON stops(cluster_id);
CREATE INDEX cd_date ON calendar_dates(date);
CREATE INDEX cr_cluster ON cluster_routes(cluster_id);
"""


def gtfs_secs(value: str) -> int:
    h, m, s = value.strip().split(":")
    return int(h) * 3600 + int(m) * 60 + int(s)


def haversine_m(lat1, lon1, lat2, lon2) -> float:
    r = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def normalise_name(name: str) -> str:
    name = re.sub(r"['\u2019.]", "", name.lower())
    return re.sub(r"[^a-z0-9]+", " ", name).strip()


def mode_for(route_type: int, short_name: str) -> str:
    if route_type == 0:
        return "luas"
    if route_type == 2:
        return "dart" if short_name.upper() == "DART" else "rail"
    return "bus"


def read_csv(zf: zipfile.ZipFile, name: str):
    if name not in zf.namelist():
        return
    with zf.open(name) as fh:
        yield from csv.DictReader(io.TextIOWrapper(fh, encoding="utf-8-sig"))


def load_feed(conn: sqlite3.Connection, prefix: str, zf: zipfile.ZipFile) -> None:
    svc = lambda sid: f"{prefix}:{sid}"  # service_ids collide across feeds
    route_modes = {}
    for r in read_csv(zf, "routes.txt"):
        mode = mode_for(int(r["route_type"]), r["route_short_name"])
        route_modes[r["route_id"]] = mode
        conn.execute(
            "INSERT OR REPLACE INTO routes VALUES (?,?,?,?,?)",
            (r["route_id"], r["route_short_name"], r["route_long_name"], int(r["route_type"]), mode),
        )
    trip_modes = {}
    rows = []
    for t in read_csv(zf, "trips.txt"):
        trip_modes[t["trip_id"]] = route_modes.get(t["route_id"], "bus")
        rows.append((t["trip_id"], t["route_id"], svc(t["service_id"]), t.get("trip_headsign", "")))
    conn.executemany("INSERT OR REPLACE INTO trips VALUES (?,?,?,?)", rows)

    stop_modes = {}
    batch = []
    for st in read_csv(zf, "stop_times.txt"):
        stop_modes.setdefault(st["stop_id"], trip_modes.get(st["trip_id"], "bus"))
        batch.append((
            st["trip_id"], st["stop_id"], int(st["stop_sequence"]),
            gtfs_secs(st["arrival_time"] or st["departure_time"]),
            gtfs_secs(st["departure_time"] or st["arrival_time"]),
            int(st.get("pickup_type") or 0), int(st.get("drop_off_type") or 0),
        ))
        if len(batch) >= 100_000:
            conn.executemany("INSERT INTO stop_times VALUES (?,?,?,?,?,?,?)", batch)
            batch.clear()
    conn.executemany("INSERT INTO stop_times VALUES (?,?,?,?,?,?,?)", batch)

    for s in read_csv(zf, "stops.txt"):
        if s.get("location_type") not in (None, "", "0"):
            continue
        conn.execute(
            "INSERT OR REPLACE INTO stops VALUES (?,?,?,?,?,?,NULL)",
            (s["stop_id"], s.get("stop_code", ""), s["stop_name"], float(s["stop_lat"]),
             float(s["stop_lon"]), stop_modes.get(s["stop_id"], "bus")),
        )
    for c in read_csv(zf, "calendar.txt"):
        days = "".join(c[d] for d in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"))
        conn.execute("INSERT OR REPLACE INTO calendar VALUES (?,?,?,?)",
                     (svc(c["service_id"]), days, c["start_date"], c["end_date"]))
    conn.executemany(
        "INSERT INTO calendar_dates VALUES (?,?,?)",
        [(svc(c["service_id"]), c["date"], int(c["exception_type"])) for c in read_csv(zf, "calendar_dates.txt")],
    )


def build_clusters(conn: sqlite3.Connection) -> None:
    """Group stops sharing a name within CLUSTER_RADIUS_M (e.g. both sides of a road)."""
    by_name = {}
    for stop_id, name, lat, lon, mode in conn.execute("SELECT stop_id, name, lat, lon, mode FROM stops"):
        by_name.setdefault(normalise_name(name), []).append((stop_id, name, lat, lon, mode))
    next_id = 1
    for key, stops in by_name.items():
        groups = []
        for stop in stops:
            for g in groups:
                if any(haversine_m(stop[2], stop[3], o[2], o[3]) <= CLUSTER_RADIUS_M for o in g):
                    g.append(stop)
                    break
            else:
                groups.append([stop])
        for g in groups:
            lat = sum(s[2] for s in g) / len(g)
            lon = sum(s[3] for s in g) / len(g)
            modes = ",".join(sorted({s[4] for s in g}))
            conn.execute("INSERT INTO clusters VALUES (?,?,?,?,?,?)",
                         (next_id, g[0][1], lat, lon, modes, key))
            conn.executemany("UPDATE stops SET cluster_id=? WHERE stop_id=?", [(next_id, s[0]) for s in g])
            next_id += 1
    # stop codes are what people see on the pole, so make them searchable
    for cid, codes in conn.execute(
        "SELECT cluster_id, group_concat(code, ' ') FROM stops WHERE code != '' GROUP BY cluster_id"
    ).fetchall():
        conn.execute("UPDATE clusters SET search = search || ' ' || ? WHERE cluster_id=?", (codes, cid))


def open_zip(src: Path | None, filename: str) -> zipfile.ZipFile:
    if src and (src / filename).exists():
        return zipfile.ZipFile(src / filename)
    print(f"downloading {filename}")
    with urllib.request.urlopen(FEED_BASE + filename, timeout=300) as resp:
        return zipfile.ZipFile(io.BytesIO(resp.read()))


def build(db_path: Path, zips: dict[str, zipfile.ZipFile]) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = db_path.with_suffix(".tmp")
    tmp.unlink(missing_ok=True)
    conn = sqlite3.connect(tmp)
    conn.execute("PRAGMA journal_mode=OFF")
    conn.execute("PRAGMA synchronous=OFF")
    conn.executescript(SCHEMA)
    for prefix, zf in zips.items():
        print(f"loading {prefix}")
        load_feed(conn, prefix, zf)
    build_clusters(conn)
    conn.executescript(INDEXES)
    conn.execute("""INSERT INTO cluster_routes
        SELECT s.cluster_id, r.short_name, r.mode, count(*) FROM stop_times st
        JOIN stops s ON s.stop_id = st.stop_id JOIN trips t ON t.trip_id = st.trip_id
        JOIN routes r ON r.route_id = t.route_id GROUP BY s.cluster_id, r.short_name, r.mode""")
    conn.commit()
    conn.execute("VACUUM")
    conn.close()
    tmp.replace(db_path)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", type=Path, help="directory containing already-downloaded GTFS zips")
    ap.add_argument("--db", type=Path, default=Path("data/gtfs.db"))
    args = ap.parse_args()
    build(args.db, {prefix: open_zip(args.src, fn) for prefix, fn in FEEDS.items()})
    print(f"wrote {args.db}")


if __name__ == "__main__":
    main()
