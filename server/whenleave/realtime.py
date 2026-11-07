"""NTA GTFS-Realtime TripUpdates client (JSON flavour of the v2 API)."""
import logging
import threading
import time
from dataclasses import dataclass, field
from typing import Callable

import httpx

log = logging.getLogger(__name__)
MAX_STALE_S = 5 * 60  # past this, predictions are worse than the timetable
TRIP_UPDATES_URL = "https://api.nationaltransport.ie/gtfsr/v2/TripUpdates?format=json"


@dataclass
class StopUpdate:
    seq: int | None
    stop_id: str | None
    arr_delay: int | None
    dep_delay: int | None
    skipped: bool


@dataclass
class TripRealtime:
    start_date: str | None
    canceled: bool
    updates: list[StopUpdate] = field(default_factory=list)

    def delay_at(self, seq: int, stop_id: str | None = None, arrival: bool = False) -> tuple[int | None, bool]:
        """Delay in seconds at a stop, propagating the latest earlier update (GTFS-R semantics)."""
        if not self.updates:
            return None, False
        chosen = None
        for u in self.updates:
            matches = (u.seq is not None and u.seq <= seq) or (u.seq is None and u.stop_id == stop_id)
            if matches:
                chosen = u
            exact = u.seq == seq or (u.seq is None and u.stop_id == stop_id)
            if exact:
                chosen = u
                break
        if chosen is None:
            chosen = self.updates[0]
        exact = chosen.seq == seq or (chosen.seq is None and chosen.stop_id == stop_id)
        primary, fallback = (chosen.arr_delay, chosen.dep_delay) if arrival else (chosen.dep_delay, chosen.arr_delay)
        delay = primary if primary is not None else fallback
        return delay, bool(exact and chosen.skipped)


def _get(d: dict, *keys):
    for k in keys:
        if k in d:
            return d[k]
    return None


def _delay(event) -> int | None:
    if not isinstance(event, dict):
        return None
    v = event.get("delay")
    return int(v) if v is not None else None


def parse_trip_updates(payload: dict) -> dict[str, TripRealtime]:
    out: dict[str, TripRealtime] = {}
    for entity in payload.get("entity") or payload.get("Entity") or []:
        tu = _get(entity, "trip_update", "tripUpdate")
        if not tu:
            continue
        trip = tu.get("trip") or {}
        trip_id = _get(trip, "trip_id", "tripId")
        if not trip_id:
            continue
        rel = (_get(trip, "schedule_relationship", "scheduleRelationship") or "SCHEDULED").upper()
        updates = []
        for stu in _get(tu, "stop_time_update", "stopTimeUpdate") or []:
            seq = _get(stu, "stop_sequence", "stopSequence")
            srel = (_get(stu, "schedule_relationship", "scheduleRelationship") or "SCHEDULED").upper()
            updates.append(StopUpdate(
                seq=int(seq) if seq is not None else None,
                stop_id=_get(stu, "stop_id", "stopId"),
                arr_delay=_delay(stu.get("arrival")),
                dep_delay=_delay(stu.get("departure")),
                skipped=srel == "SKIPPED",
            ))
        updates.sort(key=lambda u: (u.seq is None, u.seq or 0))
        out[trip_id] = TripRealtime(
            start_date=_get(trip, "start_date", "startDate"),
            canceled=rel in ("CANCELED", "CANCELLED", "DELETED"),
            updates=updates,
        )
    return out


class RealtimeFeed:
    def __init__(self, api_key: str | None, ttl: float = 60,
                 fetcher: Callable[[], dict] | None = None):
        self.api_key = api_key
        self.ttl = ttl
        self._fetcher = fetcher or self._fetch
        self._cache: dict[str, TripRealtime] = {}
        self._fetched_at = 0.0
        self._ok = False
        self._ok_at = 0.0
        self._lock = threading.Lock()

    @property
    def enabled(self) -> bool:
        return bool(self.api_key) or self._fetcher != self._fetch

    def _fetch(self) -> dict:
        resp = httpx.get(TRIP_UPDATES_URL, headers={"x-api-key": self.api_key, "Cache-Control": "no-cache"},
                         timeout=15)
        resp.raise_for_status()
        return resp.json()

    def get(self) -> dict[str, TripRealtime] | None:
        """Cached trip updates, or None when realtime is unavailable."""
        if not self.enabled:
            return None
        with self._lock:
            if time.monotonic() - self._fetched_at >= self.ttl:
                self._fetched_at = time.monotonic()
                try:
                    self._cache = parse_trip_updates(self._fetcher())
                    self._ok = True
                    self._ok_at = self._fetched_at
                except Exception as exc:  # briefly serve stale data, then fall back to schedule
                    log.warning("realtime fetch failed: %s", exc)
                    self._ok = bool(self._cache) and time.monotonic() - self._ok_at < MAX_STALE_S
            return self._cache if self._ok else None
