# Replay Map — build spec + usage

**Status: BUILT** (2026-06-18). `replay_trip.py` + `replay_template.html` at the repo root.
**Owner ask (Tyler's words):** "revisit our tracks and where/when we caught the fish. Almost
*replaying* the trip… a sexy way to show that." He's excited about this one.

## How to run it
```
# one export folder -> replay_<trip>.html inside it (auto-opens in any browser)
uv run --with pandas python replay_trip.py path/to/export_dir

# stitch a whole weekend of separate per-day export folders into one replay
uv run --with pandas python replay_trip.py --all path/to/parent_dir

# custom output / title
uv run --with pandas python replay_trip.py export_dir -o ~/Desktop/oahe.html -t "Oahe 2026"
```
Open the resulting `.html` on wifi (map tiles load from the web; everything else is embedded).

## Data cleaning the loader does automatically (reported each run)
- **Time zone:** drives ordering/gaps/clock off `timestamp_utc` and shows ONE consistent zone
  (**default Central / CDT** — Lake Oahe straddles CDT/MDT and the phone hops zones mid-trip,
  which otherwise jumps `timestamp_local` an hour and scrambles the track). Override per run
  with `--tz-offset -6` (Mountain), etc. Prints a note when a straddle is detected.
- **GPS spikes:** drops isolated teleport fixes (out-and-back jumps with falsely-confident
  accuracy) via a geometry test (a glitch snaps back near where it left; a real run moves on).
- **Car-drive trim:** drops a small, catch-free lead-in/trailing track segment split off by a
  long time gap (e.g. the drive to the lake logged before launch).
- **Coord/length sanity:** out-of-range + (0,0) coords and implausible fish lengths filtered.

## Cinematic + insight layer (v2)
- **Follow-camera** (🎥, default on): chases the boat and eases zoom by speed band; grab the
  map or hit Fit to disengage. **Slow-mo + fly-in beat** on every catch (longer for the biggest),
  with a sonar ping. **Title card** cold-open → fly-in; **end-card recap** at the finish with
  Replay + Wrapped buttons.
- **Speed sparkline** ribbon under the timeline (band-colored) + a **live telemetry chip**
  (mph / band / heading at the playhead). **Conditions-at-the-catch** in popups (boat speed,
  "slowing", heading when it hit). **Hot spots** toggle (💧) blooms gold where the boat dwelled.
- **Ambient:** water shimmer (satellite-gated), golden-hour tile grade + vignette, material
  polish + micro-interactions. **Trip Wrapped** (✨): self-drawn SVG poster → one-tap PNG (no deps).
- **Caption:** auto hero one-liner (`payload.caption`) reused by title/end-card/Wrapped.
  All degrade gracefully on a 1-catch slow day.

## What it does (shipped)
- **Satellite** basemap (toggle to dark + labels), auto **fly-in** intro, then auto-plays.
- Boat **GPS track unfolds** along a time slider, **colored by speed** (gold trolling /
  blue cruising / purple running) with a glow + a bright comet **hot-tail** at the boat head.
- **Fish pins pop in** at the exact spot+moment each was landed (ripple animation); pin
  **size/crown** marks the **biggest fish of the trip**; angler = pin color; released = hollow.
- **Multi-day stitching:** per-day toggle **chips** (with catch counts / skunk marker),
  day-colored pins + scrubber dots, automatic **overnight gap-skip** during playback.
- **Stats HUD** (catches, kept, biggest, weekend bag, miles, hours, top lure), **catch-density
  heatmap** toggle with legend, **dawn→dusk** mood tint, play/pause/scrub + speed presets,
  clickable timeline marks, spacebar/arrow-key control. Popups show length/depth/water-temp/
  lure/spot/notes — all HTML-escaped.

## Performance (benchmark + how to iterate)
- **Benchmark:** `node tests/bench.js <generated.html> [speed=800] [seconds=12] [--headful] [--json]`
  drives the replay in headless Chrome (puppeteer-core + local Chrome), blocks tile servers for
  determinism, and reports per-frame interval stats (FPS, p50/p95/p99, % over 16.7/33ms), Chrome
  main-thread counters (Layout/RecalcStyle per frame, JS heap), and render-pipeline time from a
  devtools trace. Compare the SAME file before/after a change.
- **Caveat:** automated Chrome isn't vsync-locked, so the bench measures MAIN-THREAD cost, not GPU
  compositing. GPU patterns (backdrop-filter over a moving map) must be reasoned about + reduced.
- **Loop moving forward:** change → `node tests/bench.js exports/.../replay_*.html` → confirm the
  numbers drop + `tests/harness.js` still 10/10. Use the `replay-perf-audit` workflow to re-audit.
- **Applied wins (this round):** canvas renderer (was SVG) + one shared glow/day → render pipeline
  304ms→181ms, layouts/frame 0.86→0.20, main-thread FPS 140→260. GPU: dropped `backdrop-filter` +
  caustics during active playback (restored on pause), 14px→10px blur, follow-cam panTo throttled
  to 30Hz, per-frame DOM writes change-detected + playhead moved to a composited transform.

## Tests
- `tests/make_fixtures.py` → synthetic 3-day weekend + edge cases under `/tmp/fixtures`.
- `tests/harness.js` → stubs Leaflet/DOM, drives the playback engine, asserts every catch
  reveals exactly once and speed bands segment. Run: `node tests/harness.js <generated.html>`.
- Validated against real `test_export/` and a multi-subagent adversarial review (XSS/timezone/
  coord-sanity/perf/dedup fixes all applied + verified).

## Goal

An interactive, self-contained **HTML map** that **replays a fishing day**: the boat's GPS
track unfolds along a **time slider**, and **catch pins pop in at the exact spot + moment**
each fish was caught. Built to run **at camp / at home from the exported CSVs**, and to
support a **multi-year** view as the dataset grows. Output = one `.html` file you open in a
browser.

## Inputs (the app's exports — LOCKED schema)

Per-trip export folder contains these CSVs (also see `docs/app-build-plan.md` → "Final data
schema"). **Sample/dev data lives in `test_export/`** (gitignored — a real car-drive test
near Pierre SD: ~2 catches, ~280 track points at 1 Hz; Lake Oahe area ≈ lat 44.5, lon -100.45).

**`catches.csv`** (one row per fish):
`id, uuid, timestamp_local, timestamp_utc, year, weigh_session_id, trip, fisherman, species,
kept, length_in, depth_ft, water_temp_f, lure_color1, lure_color2, bait, location_name, lat,
lon, gps_accuracy_m, heading_deg, notes`
- `timestamp_local` = `"YYYY-MM-DD HH:MM:SS"` local wall-clock (no tz) → use this for display/animation.
- `lat`/`lon` = WGS84 decimal degrees; `gps_accuracy_m` lets us filter bad fixes.
- `lat`/`lon` may be blank if a catch was saved with no GPS fix → skip those from the map (keep in any stats).

**`track.csv`** (one row per GPS fix, append-only; ~1 pt/sec moving, sparser when slow):
`timestamp_utc, timestamp_local, trip, weigh_session_id, lat, lon, accuracy_m, altitude_m,
speed_mps, course_deg`
- `speed_mps` can drive troll-vs-run coloring; `course_deg` = heading; both blank when invalid.

**`daily_weights.csv`** (optional context): `weigh_session_id, weigh_date, trip,
daily_wt_lbs, day_inches, daily_wt_per_inch, n_catches_logged, notes`.

Join key between catches and track = **timestamp** (a catch's location is its own `lat/lon`;
no join strictly needed, but `weigh_session_id`/`trip` group a day/trip).

## Visualization design

**Single-day replay (primary):**
- Auto-center/zoom to the data bounds.
- **Boat track** as a polyline that **unfolds over time** (animated). Optionally color the
  track by `speed_mps` (slow=trolling, fast=running) or by hour.
- **Catch markers** appear at their `timestamp_local`, at their `lat/lon`:
  - **size** ∝ `length_in`, **color** = `fisherman` (categorical, with legend),
  - **popup**: local time, fisherman, species, length_in, depth_ft, lure_color1/2,
    water_temp_f, location_name.
  - released fish (`kept==false`) → distinct marker (hollow/outline).
- **Time slider** plays the day: path draws in, pins drop as time passes.

**Multi-year / multi-trip:**
- Layer toggle (LayerControl) per `trip`/`year`, OR
- **Catch-density heatmap** across all years (Folium `HeatMap`) — "where do fish come from."
- Year-over-year "best spots."

**Quality filters:** drop track points with `accuracy_m` > ~30 m and catches with
`gps_accuracy_m` > ~30 m from the map (note how many dropped; don't silently truncate).

## Tech approach

- **Python via `uv`** (per project convention): e.g.
  `uv run --with folium --with pandas python replay_trip.py <export_dir>`
- **Recommended:** **Folium + `TimestampedGeoJson`** plugin → the "unfolding path + pins
  appearing" time-slider replay in one self-contained HTML. (Alternative: Plotly
  `scatter_mapbox` with `animation_frame` and `mapbox_style="open-street-map"` — no token
  needed; gives a play/slider too. Pick Folium for the replay feel; Plotly is a fine fallback.)
- **Base tiles:** default OSM tiles need internet (fine at home/camp wifi). Note this; an
  offline-tiles mode (pre-downloaded/satellite) is a future nice-to-have, not v1.
- Output: `replay_<trip>.html` (and a multi-year `replay_all.html`).

## Suggested CLI / behavior

- `replay_trip.py <export_dir>` → builds the single-trip replay from that folder's CSVs.
- `replay_trip.py --all <parent_dir>` → globs per-trip subfolders → layered/heatmap multi-year view.
- Robust to: missing `daily_weights.csv`, blank GPS on some catches, blank `speed/course`.
- Validate against `test_export/` first (it should produce a sensible little replay of the drive).

## Build steps (for me, post-compaction)

1. Read this file + `test_export/catches.csv` & `track.csv` to confirm schema.
2. Write `replay_trip.py` (Folium + TimestampedGeoJson), run it on `test_export/` via `uv`.
3. Open/verify the HTML renders track + catch pins + time slider.
4. Add multi-year/heatmap mode. Commit to `iHusk/fishing-analysis`.

## Related

- Schema + project context: `docs/app-build-plan.md`, `docs/methodology.md`.
- App that produces the data: private repo `iHusk/FishingLogger` (mirror in `app/`).
- Memory: `fishing-logger-app.md`.
