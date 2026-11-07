import os
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query

from . import planner
from .realtime import RealtimeFeed

ROOT = Path(__file__).resolve().parent.parent


def create_app(db_path: str | None = None, feed: RealtimeFeed | None = None,
               clock=lambda: datetime.now(planner.TZ)) -> FastAPI:
    db_path = db_path or os.environ.get("WHENLEAVE_DB", str(ROOT / "data" / "gtfs.db"))
    state = {}

    @asynccontextmanager
    async def lifespan(app):
        if not Path(db_path).exists():
            raise RuntimeError(f"{db_path} missing; run `python -m whenleave.ingest` first")
        state["db"] = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, check_same_thread=False)
        state["feed"] = feed or RealtimeFeed(os.environ.get("NTA_API_KEY"))
        yield
        state["db"].close()

    app = FastAPI(title="Slí transit API", lifespan=lifespan)

    def cluster_or_404(cid: int) -> dict:
        c = planner.get_cluster(state["db"], cid)
        if not c:
            raise HTTPException(404, "unknown stop")
        return c

    @app.get("/api/health")
    def health():
        return {"ok": True, "realtime": state["feed"].enabled}

    @app.get("/api/stops/search")
    def search(q: str = Query(..., min_length=1, max_length=80)):
        return planner.search_stops(state["db"], q)

    @app.get("/api/stops/near")
    def near(lat: float = Query(..., ge=-90, le=90), lon: float = Query(..., ge=-180, le=180),
             limit: int = Query(8, ge=1, le=30)):
        return planner.nearby_stops(state["db"], lat, lon, limit=limit)

    @app.get("/api/stops/{stop_id}/arrivals")
    def arrivals(stop_id: int, window: int = Query(90, ge=10, le=360)):
        stop = cluster_or_404(stop_id)
        rt = state["feed"].get()
        now = clock()
        return {"now": now.isoformat(), "stop": stop, "realtime": rt is not None,
                "arrivals": planner.stop_arrivals(state["db"], stop_id, now, window_min=window, realtime=rt)}

    @app.get("/api/departures")
    def deps(from_: int = Query(..., alias="from"), to: int = Query(...),
             walk: int = Query(5, ge=0, le=60), window: int = Query(120, ge=10, le=360)):
        origin, dest = cluster_or_404(from_), cluster_or_404(to)
        rt = state["feed"].get()
        now = clock()
        return {"now": now.isoformat(), "from": origin, "to": dest, "realtime": rt is not None,
                "departures": planner.departures(state["db"], from_, to, now, walk_min=walk,
                                                 window_min=window, realtime=rt)}

    @app.get("/api/trip")
    def trip(from_lat: float, from_lon: float, to_lat: float, to_lon: float,
             arrive_by: datetime | None = None):
        rt = state["feed"].get()
        now = clock()
        if arrive_by and arrive_by.tzinfo is None:
            arrive_by = arrive_by.replace(tzinfo=planner.TZ)
        return {"now": now.isoformat(), "realtime": rt is not None,
                **planner.plan_trip(state["db"], from_lat, from_lon, to_lat, to_lon, now,
                                    arrive_by=arrive_by, realtime=rt)}

    return app


app = create_app()
