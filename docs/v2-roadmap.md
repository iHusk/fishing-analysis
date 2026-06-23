# v2 Roadmap — replay/app/analytics next wave

**Status:** written to Linear (project *Fishing Logger*, team HayesHousehold / HAY) on 2026-06-21.
Each `### ISSUE` below maps to one Linear issue; IDs in the table. Decisions were locked with the
owner on 2026-06-21.

| ID | Issue | ID | Issue |
|----|-------|----|-------|
| [HAY-119](https://linear.app/hayeshousehold/issue/HAY-119) | INFRA-1 | [HAY-126](https://linear.app/hayeshousehold/issue/HAY-126) | REPLAY-2 |
| [HAY-120](https://linear.app/hayeshousehold/issue/HAY-120) | DATA-1 | [HAY-127](https://linear.app/hayeshousehold/issue/HAY-127) | REPLAY-3 |
| [HAY-121](https://linear.app/hayeshousehold/issue/HAY-121) | APP-1 | [HAY-128](https://linear.app/hayeshousehold/issue/HAY-128) | WEB-3 |
| [HAY-122](https://linear.app/hayeshousehold/issue/HAY-122) | APP-2 | [HAY-129](https://linear.app/hayeshousehold/issue/HAY-129) | REPLAY-1 |
| [HAY-123](https://linear.app/hayeshousehold/issue/HAY-123) | DATA-2 | [HAY-130](https://linear.app/hayeshousehold/issue/HAY-130) | APP-3 |
| [HAY-124](https://linear.app/hayeshousehold/issue/HAY-124) | WEB-2 | [HAY-131](https://linear.app/hayeshousehold/issue/HAY-131) | PIPE-1 |
| [HAY-125](https://linear.app/hayeshousehold/issue/HAY-125) | WEB-1 | [HAY-132](https://linear.app/hayeshousehold/issue/HAY-132) | REPLAY-4 |

## Locked decisions (read first)
1. **Historical data is sacred.** `fishing-trip.xlsx` and the app's exported CSVs are the durable
   source of truth and are **never** overwritten. All migrations/pipelines *derive* new files
   alongside them.
2. **Target species = a multiselect list** (default `["walleye"]`), configurable per replay.
   Non-targets render smaller/dimmer. **No automatic size-based promotion** — instead a manual
   **"star this catch"** override lets a one-off trophy (big pike/bass) stay highlighted. The
   star lives in the trip-prep **sidecar** (a list of catch UUIDs), so it needs **no app/schema
   change**.
3. **Notes split:** quick **day notes stay in the app** (already in `daily_weights.csv`); the
   reflective **whole-trip review is a post-trip laptop sidecar** (`trip_notes.json`) merged by
   the pipeline.
4. **Lake areas are phased:** (A) web polygon editor → `areas.geojson`; (B) label catches by area
   in replay/analytics; (C) *later* the iOS app reads the geojson to auto-fill `location_name`.
5. **Analytics folds in a non-destructive historical migration** of the 3 prior seasons into the
   new schema (so "avg wt/inch across years" has real data) — `xlsx` stays untouched.
6. **Length/depth input → drag-a-ruler (tape-measure) control** replacing the stepper arrows.
7. **Outing split = gap-based, day as floor:** a new outing starts on a long stationary/off-water
   pause (>~60 min, no track movement) or overnight; collapses to one-outing-per-day when there's
   no mid-day break.
8. **Web stack = hybrid:** replay + analytics stay **generated static HTML** (offline-friendly);
   a **single-file FastAPI app** serves only the *authoring* tools (save `areas.geojson` /
   `trip_notes.json`). A **`justfile`** fronts every command. **No DB** — files stay the source of
   truth.

## Architecture sketch
```
SOURCE (durable, never mutated)
  fishing-trip.xlsx              # historical record (3 seasons)
  exports/2026/<day>/*.csv       # app exports (accumulating)

DERIVED (regenerable)
  exports/2026/trip_notes.json   # day + trip-review notes (laptop)
  areas/areas.geojson            # named lake areas (polygon editor)
  build/<trip>/replay_bundle.json# replay-prep pipeline output (notes + area labels merged)
  replay_<day>.html              # static, Python-generated
  analytics.html                 # static, Python-generated

TOOLS
  server.py (FastAPI ~50 lines)  # POST /areas, POST /notes  (authoring only, localhost)
  justfile                       # just replay / analytics / areas / notes / ingest / bench / test
```

---

## Issues

### INFRA-1 — `justfile` + thin FastAPI authoring server scaffold
**Labels:** infra, web
**Why:** Foundation for the authoring tools (areas/notes editors) and a one-command front door for
every workflow.
**Scope / acceptance:**
- `justfile` with recipes: `replay <day>`, `analytics`, `areas`, `notes`, `ingest <day>`,
  `bench <html>`, `test`.
- `server.py`: single-file FastAPI, serves the static authoring pages on localhost and exposes
  `POST /areas` (writes `areas/areas.geojson`) and `POST /notes` (writes
  `exports/<year>/trip_notes.json`). Writes are atomic; never touches source CSV/xlsx.
- Run via `just areas` / `just notes`; works fully offline (localhost only).
**Depends on:** none. **Blocks:** WEB-2, DATA-2 (notes editor).

### DATA-1 — Non-destructive migration of 3 historical seasons → new schema
**Labels:** data, analysis
**Why:** "avg weight-per-inch across years" needs the prior seasons in the new clean schema.
**Scope / acceptance:**
- Read `fishing-trip.xlsx` **read-only**; emit derived per-season CSVs on the locked schema into a
  `historical/` (or `exports/<year>/`) folder. The xlsx is **not modified**.
- Rewrite `load_data()` for the new schema: group calibration by `weigh_session_id`, **exclude
  `kept==false` from the bag denominator**, filter anchor rows on `daily_wt_lbs.notna()`.
- Sanity report: per-year catch counts + bag weights reconcile with the xlsx within tolerance.
**Depends on:** none. **Blocks:** WEB-1.

### DATA-2 — Notes model (day notes + whole-trip review sidecar)
**Labels:** data, web
**Why:** Capture per-day conditions and a reflective trip review (e.g. "next year push north to
Bob's / Bush's Landing") without bloating the app.
**Scope / acceptance:**
- `trip_notes.json` schema: `{ trip, review, days: { <weigh_session_id>: <note> } }`.
- Day notes already flow from the app (`daily_weights.csv`); pipeline reconciles app day-notes with
  any sidecar day-notes (sidecar wins on conflict, logged).
- Simple notes editor page served by `server.py` (`POST /notes`) — optional but preferred over
  hand-editing JSON.
**Depends on:** INFRA-1 (for the editor). **Blocks:** rendering in REPLAY-1 plaques + WEB-1.

### PIPE-1 — Replay-prep pipeline (derive a clean replay bundle)
**Labels:** data, replay
**Why:** Decouple the replay front-end from raw CSV quirks; merge notes + area labels once.
**Scope / acceptance:**
- `just ingest <day>` reads source CSVs (durable), applies existing cleaning (tz ordering,
  despike, orphan-trim), merges `trip_notes.json` + `areas.geojson` labels + the star-override
  list, and writes `build/<trip>/replay_bundle.json`.
- `replay_trip.py` can consume the bundle (fast path) **or** raw CSVs (today's path) — bundle is
  an optimization, source stays authoritative.
- Source files are inputs only; pipeline never writes back into `exports/.../*.csv`.
**Depends on:** DATA-2, WEB-3 (area labels) — can land incrementally.

### REPLAY-1 — Outing detection + per-outing plaques + master weekend plaque
**Labels:** replay
**Why:** Today the replay "renders the night" (the dead overnight gap). Instead, segment the
weekend into on-water outings, recap each, then a finale.
**Scope / acceptance:**
- Detect outings: split on a long stationary/off-water pause (>~60 min, no track movement) or
  overnight (date change); floor = one outing per day.
- At each outing's end, a small **day/outing plaque** animates in (catches, bag, biggest, a line
  of the day note). Skip the dead gap instead of scrubbing through it.
- At the trip's end, the existing end-card becomes the **master weekend plaque** (weekend bag,
  per-day breakdown, trip-review note).
**Depends on:** DATA-2 (for plaque note text). Touches `replay_template.html` + `replay_trip.py`.

### REPLAY-2 — Target-species emphasis
**Labels:** replay
**Why:** Walleye is the point; catfish/drum/perch are noise on the map.
**Scope / acceptance:**
- `target_species` (multiselect, default `["walleye"]`) in the payload/config.
- Target catches: full-size, full-opacity pins (current walleye look). Non-targets: **smaller +
  lower opacity** glyphs, still visible.
- **Star override:** a sidecar list of catch UUIDs renders at full emphasis regardless of species
  (the rare trophy pike/bass). No app/schema change.
- Crown (biggest) logic respects target set: the trip "biggest" crowns among targets+starred.
**Depends on:** PIPE-1 (star list) — can stub from a constant initially. Touches `replay_template.html`.

### REPLAY-3 — Heatmap driven by target species
**Labels:** replay
**Why:** "Where do the walleye come from" — non-targets shouldn't dilute the heat.
**Scope / acceptance:**
- Heatmap weights only target (+ starred) catches by default; a toggle can show all.
- Legend notes the active species filter.
**Depends on:** REPLAY-2 (shared target config).

### REPLAY-4 — Cross-day opacity + weekend-review layering
**Labels:** replay
**Why:** When day 2 plays, day 1's track shouldn't compete at full strength; the weekend review
needs a deliberate all-days look.
**Scope / acceptance:**
- During playback, the currently-playing day's track/pins are full-opacity; **earlier days fade**
  to a low ambient opacity.
- Define the **weekend-review** state: all days shown together at a balanced opacity with per-day
  color legend (used by the master plaque).
**Depends on:** REPLAY-1 (outing/day model). Touches `replay_template.html`.

### WEB-1 — Analytics page (static, interactive filters)
**Labels:** analytics, web
**Why:** Understand fish health/quality over time; headline metric = **avg weight-per-inch across
years**.
**Scope / acceptance:**
- `build_analytics.py` → `analytics.html` (static, data baked in as JSON; Chart lib from CDN).
- Interactive filters: year, species, fisherman, kept/released, location/area.
- Core charts: avg wt/inch by year (the YoY quality trend), length distribution, catch counts,
  bag by day/trip. Degrades gracefully with sparse years.
**Depends on:** DATA-1 (multi-year data).

### WEB-2 — Lake-area polygon editor → `areas.geojson`
**Labels:** web, maps
**Why:** Name the regions of Oahe so catches/areas are human-readable everywhere.
**Scope / acceptance:**
- `map-areas.html` (Leaflet + draw control) served by `server.py`; draw/edit/name polygons.
- **Save** posts to `POST /areas` → writes `areas/areas.geojson` (FeatureCollection, each feature
  has a `name`). Reload restores existing areas for editing.
- `just areas` opens it.
**Depends on:** INFRA-1.

### WEB-3 — Label catches by area in replay + analytics
**Labels:** web, replay, analytics
**Why:** Turn raw lat/lon into "Bob's Landing" across the views.
**Scope / acceptance:**
- Point-in-polygon assigns each catch an `area` from `areas.geojson` (in PIPE-1 / build step).
- Replay popups + analytics filters/labels use the area name when present.
**Depends on:** WEB-2.

### APP-1 — Freeze catch GPS at "Log Fish" tap
**Labels:** app, ios
**Why:** Right now `loc.current` keeps updating while the catch form is open
(`CatchEntryView.swift:209`), so the saved point drifts as the boat moves during data entry.
**Scope / acceptance:**
- On opening the catch form (the "Log Fish" tap), **capture and freeze** the precise fix at that
  instant; display it locked; save that frozen coordinate on Submit.
- A small "re-tag here" affordance if the user wants to re-capture deliberately.
- Background track continues normally; only the *catch* coordinate is frozen.
**Depends on:** none.

### APP-2 — Drag-a-ruler length/depth input
**Labels:** app, ios
**Why:** The `Stepper` arrows (`CatchEntryView.swift:97,105`) are slow/fiddly with wet, cold hands.
**Scope / acceptance:**
- Replace the length stepper with a **horizontal tape-measure control**: drag to set, big numeric
  readout, snaps to 0.25 in; depth reuses the same control (1 ft step, larger range).
- Keep carry-forward seeding; keep values within current bounds.
**Depends on:** none.

### APP-3 (later) — App ingests `areas.geojson` to auto-fill `location_name`
**Labels:** app, ios, maps
**Why:** Auto-name a catch's spot from the named lake areas (phase C of the lake-areas plan).
**How the phone gets the polygons (no server on the water):**
- **Primary: bundle `areas.geojson` into the app at build time.** Since the app is rebuilt before
  every trip (7-day profile), each build ships the latest areas — zero runtime infra, fully
  offline. Drop the file into the Xcode project resources as part of the pre-trip build.
- **Secondary: Files/share-sheet import** — a button that imports an `areas.geojson` from the
  Files app (AirDrop it to the phone) so areas can update **without** a rebuild.
- **Not** a live server connection — the app must work with no network on the lake.
- On catch save, point-in-polygon against the loaded areas pre-fills `location_name` (still
  user-editable).
**Depends on:** WEB-2 (the geojson).

---

## Dependency graph
```
INFRA-1 ─┬─> WEB-2 ──> WEB-3 ──┐
         └─> DATA-2 ──┐        ├─> PIPE-1 ─> (REPLAY-1..4 fast path)
DATA-1 ──> WEB-1      │        │
                      └────────┴─> REPLAY-1 ─> REPLAY-4
REPLAY-2 ─> REPLAY-3
WEB-2 ─> APP-3
APP-1, APP-2  (independent)
```

## Suggested first cut
INFRA-1 → (DATA-1 ‖ WEB-2) → REPLAY-2/3 (quick visual wins) → REPLAY-1/4 → WEB-1/3 → APP-1/2 →
APP-3 last.
