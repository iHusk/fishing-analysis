# fishing-analysis

Tools and data for a personal Lake Oahe (SD) walleye trip: an **offline iPhone catch/track
logger**, a **data pipeline + weight model**, and an animated **trip replay map**. Public repo;
the runnable iOS Xcode project lives in the private repo `iHusk/FishingLogger`.

> **Next season — quick start:** picking this back up after a year away? Start with the
> checklist playbook in **[`docs/next-season.md`](docs/next-season.md)**.

## What's here

| Piece | Where | What it is |
|---|---|---|
| **Trip replay map** | `replay_trip.py`, `replay_template.html` | Turns an app export into ONE self-contained HTML: satellite map, GPS track that unfolds on a time slider colored by speed, fish pins that pop in, multi-day stitching, area labels, target-species emphasis + heatmap, per-outing/weekend plaques, stats and a satellite-backed Wrapped poster. |
| **Analytics page** | `build_analytics.py` → `analytics.html` | Self-contained interactive page (Chart.js + Plotly from CDN): measured vs. modeled weight-per-inch by year, length-vs-depth, time-of-day, depth/length violins, length histogram; filters by year/species/fisherman/area/kept. |
| **Authoring server** | `server.py`, `map-areas.html`, `notes.html` | Single-file localhost FastAPI (`127.0.0.1`) that serves ONLY the authoring tools: a polygon **area editor** (`POST/GET /areas` → `areas/areas.geojson`) and a **trip-notes editor** (`POST/GET /notes` → `exports/<year>/trip_notes.json`). Atomic writes; never touches source CSV/xlsx. |
| **Replay-prep pipeline** | `ingest.py`, `areas.py`, `replay_config.json` | `just ingest <day>` cleans a day and derives `build/<trip>/replay_bundle.json` (area labels via pure-Python point-in-polygon, the star list + target species from `replay_config.json`, merged notes). Source CSVs stay authoritative. |
| **Command front-end** | `justfile` | `just replay / analytics / areas / notes / ingest / bench / test`. |
| **iOS logger app** | `app/` (source + tests) | Native SwiftUI + Core Location offline logger. Buildable project: private `iHusk/FishingLogger`. |
| **Weight model + analysis** | `fishing-trip.xlsx`, `analysis.py`, notebook | Historical bag-weight model (power curve calibrated to measured daily bags). The xlsx is the **historical record — don't break it.** |
| **Historical data** | `scripts/migrate_history.py` → `historical/{2023,2024,2025}/` | Non-destructive migration of the 3 prior xlsx seasons into the locked CSV schema. `analysis.py load_history()` dedups the accumulating exports + folds in the historical years. |
| **Benchmark** | `tests/bench.js` | Headless-Chrome performance benchmark for the replay map. |
| **Tests** | `tests/` | `make_fixtures.py` + `harness.js` (replay correctness); `shot_wrapped.js` (headless screenshot verifier for the Wrapped poster with the satellite map on); `test_server.py`, `test_reconcile_history.py` (pytest); Swift package tests for the app core. |

## Docs
- `docs/replay-map-spec.md` — replay map: usage, v2 features, data cleaning, performance, tests.
- `docs/v2-roadmap.md` — the v2 wave issues + status.
- `docs/notes-schema.md` — `trip_notes.json` schema + the day-note merge rule.
- `docs/xcode-mcp-workflow.md` — **iOS app: build, sideload (free Apple ID), and the Xcode MCP workflow.**
- `docs/app-build-plan.md` — the app's locked decisions, architecture, and final data schema.
- `docs/methodology.md` — canonical durable reference (schema, weight model, data-quality, dev notes).
- `docs/adr/` — architecture decision records (e.g. the weight curve).

## Use the replay map
```bash
# one export folder -> replay_<name>.html inside it (the app export accumulates, so the
# LATEST dated folder is the whole trip; day chips toggle each day)
uv run --with pandas python replay_trip.py exports/2026/20260620 -t "Lake Oahe · Jun 18–20 2026"

# time zone: defaults to Central (CDT). Lake Oahe straddles CDT/MDT and the phone hops zones
# mid-trip; everything is ordered off timestamp_utc and shown in one consistent zone.
#   --tz-offset -6   # show Mountain instead
```
Then open the generated `.html` (map tiles load from the web; everything else is embedded).
Per-trip gotcha: AirDrop'd files arrive as `catches 3.csv` / `track 3.csv` — copy to the
canonical `catches.csv` / `track.csv` first.

## Commands (`justfile`)
```bash
just replay 20260620   # render exports/2026/20260620 -> replay HTML in that folder
just analytics         # build_analytics.py -> analytics.html
just areas             # serve the polygon area editor at http://127.0.0.1:8765/
just notes             # serve the trip-notes editor at http://127.0.0.1:8765/notes
just ingest 20260620   # derive build/<trip>/replay_bundle.json (areas + stars + notes)
just bench <html>      # headless perf benchmark
just test              # node tests/harness.js + Swift package tests
```
`just areas` / `just notes` run the localhost-only authoring server (`server.py`); both
work fully offline and write atomically (areas → `areas/areas.geojson`, notes →
`exports/<year>/trip_notes.json`). Source CSV/xlsx are never touched.

## Migrate the historical seasons
```bash
uv run python scripts/migrate_history.py   # xlsx (read-only) -> historical/{2023,2024,2025}/*.csv
```
Non-destructive: the xlsx is never written. `analysis.py load_history()` then dedups the
accumulating exports, excludes `kept==false` from the bag denominator, derives blank
`day_inches` from the kept-walleye bag, and applies `NET_TARE_LBS_BY_YEAR`.

## Benchmark the replay map
```bash
node tests/bench.js exports/2026/20260620/replay_20260620.html 800 12   # headless, deterministic
node tests/bench.js <html> --headful        # real GPU       --json     # for tracking
```
Reports FPS, frame-time percentiles, % dropped frames, per-frame Layout/recalc, and render
pipeline time. Loop: change → bench → confirm numbers drop + `node tests/harness.js` 10/10.

## Run the tests
```bash
node tests/harness.js <generated.html>                         # replay playback correctness
node tests/shot_wrapped.js <generated.html> /tmp/wrapped.png   # Wrapped poster w/ satellite map on
uv run pytest tests/                                           # server + history-reconcile (pytest)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # app core (in app/FishingLoggerCore)
uv run python tests/make_fixtures.py /tmp/fixtures             # regenerate synthetic test data
```

## Conventions
- **Python via `uv`** (`uv run --with pandas …`). **Dependency-free front end** (Leaflet 1.9 +
  leaflet.heat from CDN only; no build step). `node_modules/` (puppeteer-core for the bench) is gitignored.
- **Locked CSV schema** shared by the app and the tools — see `docs/app-build-plan.md`.
- `exports/2026/<YYYYMMDD>/` holds each trip day's export (a superset of prior days) + its replay.

## Pending / follow-ups
The v2 wave is shipped: the historical migration + `load_history()`, the analytics page,
the lake-area editor + area labels, target-species emphasis/heatmap, outing/weekend
plaques, cross-day fade, and the satellite-backed Wrapped poster are all **done**.

Remaining:
- **APP-3** (backlog) — the iOS app ingests `areas.geojson` to auto-fill `location_name`
  (bundle the geojson at build time / Files import; point-in-polygon on save). No server on
  the water. See `docs/v2-roadmap.md`.
- **Future**: multi-year season views + best-spots as the dataset grows; optional re-tag
  affordance on the frozen catch GPS.
