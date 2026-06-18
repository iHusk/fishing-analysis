# Replay Map — build spec (handoff)

**Status:** not built yet. Post-compaction, point me at this file and I'll build `replay_trip.py`.
**Owner ask (Tyler's words):** "revisit our tracks and where/when we caught the fish. Almost
*replaying* the trip… a sexy way to show that." He's excited about this one.

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
