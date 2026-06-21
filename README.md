# fishing-analysis

Tools and data for a personal Lake Oahe (SD) walleye trip: an **offline iPhone catch/track
logger**, a **data pipeline + weight model**, and an animated **trip replay map**. Public repo;
the runnable iOS Xcode project lives in the private repo `iHusk/FishingLogger`.

## What's here

| Piece | Where | What it is |
|---|---|---|
| **Trip replay map** | `replay_trip.py`, `replay_template.html` | Turns an app export into ONE self-contained HTML: satellite map, GPS track that unfolds on a time slider colored by speed, fish pins that pop in, multi-day stitching, stats/heatmap/Wrapped poster. |
| **iOS logger app** | `app/` (source + 27 tests) | Native SwiftUI + Core Location offline logger. Buildable project: private `iHusk/FishingLogger`. |
| **Weight model + analysis** | `fishing-trip.xlsx`, `analysis.py`, notebook | Historical bag-weight model (power curve calibrated to measured daily bags). The xlsx is the **historical record — don't break it.** |
| **Benchmark** | `tests/bench.js` | Headless-Chrome performance benchmark for the replay map. |
| **Tests** | `tests/` | `make_fixtures.py` + `harness.js` (replay correctness, 10 fixtures); Swift package tests for the app core. |

## Docs
- `docs/replay-map-spec.md` — replay map: usage, features, data cleaning, performance, tests.
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
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # app core (in app/FishingLoggerCore)
uv run python tests/make_fixtures.py /tmp/fixtures             # regenerate synthetic test data
```

## Conventions
- **Python via `uv`** (`uv run --with pandas …`). **Dependency-free front end** (Leaflet 1.9 +
  leaflet.heat from CDN only; no build step). `node_modules/` (puppeteer-core for the bench) is gitignored.
- **Locked CSV schema** shared by the app and the tools — see `docs/app-build-plan.md`.
- `exports/2026/<YYYYMMDD>/` holds each trip day's export (a superset of prior days) + its replay.

## Pending / follow-ups
- **Replay webpage**: a few tweaks requested (to be specified) — see "Pending changes" in
  `docs/replay-map-spec.md`.
- **`load_data()` rewrite** (post-trip): point the historical analysis at the new clean CSV
  schema and migrate the 3 historical years; group calibration by `weigh_session_id`, exclude
  `kept==false` from the bag denominator, filter anchor rows on `daily_wt_lbs.notna()`.
- **Season `--all` view + heatmap** once the multi-trip dataset grows.
