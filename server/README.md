# Slí transit server

Small FastAPI service behind the iOS app's `LiveTransitService`. It loads the official
TFI GTFS timetables (Dublin Bus, Luas, Irish Rail incl. DART) into SQLite and, when an
NTA API key is set, merges GTFS-Realtime delays and cancellations.

```sh
cd server
pip install -r requirements.txt
python -m whenleave.ingest            # downloads feeds -> data/gtfs.db (~20 s, ~300 MB)
NTA_API_KEY=... uvicorn whenleave.app:app --port 8000   # key optional; without it times are "Timetable"
pytest -q
```

Get a key at https://developer.nationaltransport.ie (GTFS-R product).

## Endpoints
| Endpoint | Purpose |
|---|---|
| `GET /api/stops/search?q=` | Stop name or bus pole number |
| `GET /api/stops/near?lat=&lon=` | Nearest stops |
| `GET /api/stops/{id}/arrivals` | Next departures from a stop (all platforms/poles) |
| `GET /api/departures?from=&to=&walk=` | Direct A→B departures with "leave in" incl. walk |
| `GET /api/trip?from_lat=&from_lon=&to_lat=&to_lon=&arrive_by=` | Door-to-door: walk → one vehicle → walk |

Stop ids are *clusters*: same-named stops within 350 m (both sides of a road, Luas
platforms) are grouped so riders don't have to pick the right pole.

Every departure has a `status`:
- `live`: the vehicle is tracked
- `unconfirmed`: due within 20 min but not tracked while the live feed is up (the "ghost bus" risk)
- `scheduled`: timetable only
- `cancelled`
