import sys
import zipfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from whenleave import ingest  # noqa: E402

FEED = {
    "agency.txt": "agency_id,agency_name,agency_url,agency_timezone\n1,Test Bus,https://x,Europe/Dublin\n",
    "routes.txt": "route_id,agency_id,route_short_name,route_long_name,route_type\n"
                  "R46,1,46A,Main - Market,3\nRDART,1,DART,Coast,2\n",
    "stops.txt": "stop_id,stop_code,stop_name,stop_lat,stop_lon,location_type\n"
                 "A1,1234,Main St,53.3000,-6.2000,\n"
                 "A2,1235,Main St,53.3002,-6.2003,\n"
                 "B1,2001,Market Sq,53.3100,-6.2000,\n"
                 "C1,999001,Seaside,53.3300,-6.1500,\n"
                 "M1,3001,Main St,53.4000,-6.4000,\n",
    "calendar.txt": "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n"
                    "WK,1,1,1,1,1,0,0,20260101,20271231\n",
    "calendar_dates.txt": "service_id,date,exception_type\nWK,20261225,2\n",
    "trips.txt": "route_id,service_id,trip_id,trip_headsign,direction_id\n"
                 "R46,WK,T1,Market,0\nR46,WK,T2,Main,1\nR46,WK,T3,Market,0\nRDART,WK,D1,Seaside,0\n",
    "stop_times.txt": "trip_id,arrival_time,departure_time,stop_id,stop_sequence,pickup_type,drop_off_type\n"
                      "T1,08:00:00,08:00:00,A1,1,0,1\nT1,08:10:00,08:10:00,B1,2,1,0\n"
                      "T2,08:30:00,08:30:00,B1,1,0,1\nT2,08:40:00,08:40:00,A2,2,1,0\n"
                      "T3,24:30:00,24:30:00,A1,1,0,1\nT3,24:40:00,24:40:00,B1,2,1,0\n"
                      "D1,08:05:00,08:05:00,B1,1,0,1\nD1,08:25:00,08:25:00,C1,2,1,0\n",
}


@pytest.fixture(scope="session")
def db_path(tmp_path_factory) -> Path:
    tmp = tmp_path_factory.mktemp("gtfs")
    zpath = tmp / "feed.zip"
    with zipfile.ZipFile(zpath, "w") as zf:
        for name, body in FEED.items():
            zf.writestr(name, body)
    db = tmp / "gtfs.db"
    ingest.build(db, {"bus": zipfile.ZipFile(zpath)})
    return db


@pytest.fixture
def conn(db_path):
    import sqlite3
    c = sqlite3.connect(db_path)
    yield c
    c.close()
