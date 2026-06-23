# Next-Season Playbook

A skim-able checklist to pick this project back up FAST after a year away. You won't
remember the details — you don't have to. Work top to bottom.

> One-time setup details for the phone live in `docs/xcode-mcp-workflow.md`. Data
> gotchas live in `docs/methodology.md`. This page is the *runbook*.

---

## 1. Before the trip (on land, with wifi)

- [ ] **Rebuild + sideload the app.** Free Apple ID = a **7-day** provisioning profile, so
      it must be re-installed shortly before the trip. Open the Xcode project, build via the
      xcode MCP, install to the phone. Full walkthrough: `docs/xcode-mcp-workflow.md`.
- [ ] **Do NOT delete the app first.** Same bundle ID preserves the sandbox/data. Rebuilding
      just refreshes the profile.
- [ ] **Fallback:** if signing breaks mid-trip, a $99/yr paid Apple account can re-sign the
      same evening.
- [ ] **At the dock:** hit **Start Track**. Don't swipe the app closed (force-quit kills
      background tracking; backgrounding is fine).
- [ ] **Jot the bag weight on paper** each day as a backup.

---

## 2. After each day / post-trip (back on land)

**Get the exports off the phone (AirDrop), then make them canonical:**

- [ ] AirDrop arrives de-duped as `catches 3.csv`, `track 3.csv`, etc. → **rename** to the
      canonical `catches.csv` / `track.csv` (+ `daily_weights.csv`).
- [ ] The export **accumulates** — each day's folder is a *superset* of all prior days. Use
      the **LATEST dated folder** as the whole trip. **Never `--all` across the dated folders**
      (they overlap and double-count).
- [ ] Drop them into `exports/2026/<YYYYMMDD>/` (one folder per export day).

**Then run the tools (copy-paste):**

```bash
just replay 20260620     # render exports/2026/20260620 -> replay_<day>.html in that folder
just analytics           # build_analytics.py -> analytics.html
just areas               # polygon editor: draw/name spots -> areas/areas.geojson
just notes               # trip-notes editor -> exports/<year>/trip_notes.json
```

- [ ] Draw/name any new spots in **`just areas`**, write the trip review in **`just notes`**
      (or hand-edit `exports/<year>/trip_notes.json`).
- [ ] Re-run `just replay <day>` / `just analytics` so the new areas + notes show up.
- [ ] (Optional) `just ingest <day>` pre-builds `build/<trip>/replay_bundle.json` (faster
      replay; source CSVs stay authoritative either way).

---

## 3. Data gotchas to remember

Full detail in `docs/methodology.md` → "Known data-quality issues".

| Gotcha | One-liner |
|---|---|
| **Net-tare** | 2023–25 bags were weighed **with the ~2 lb net** on the scale; 2026+ is net-free. Set `NET_TARE_LBS_BY_YEAR` per year in `analysis.py`; it's subtracted per weigh session. |
| **Accumulating export** | Folders are supersets → `load_history()` **dedups by catch** before any rollup. Run off the LATEST folder; never `--all` across dated folders. |
| **2026 `day_inches`** | App leaves it blank → derived by summing **kept-walleye** lengths per weigh session. |
| **Time-zone straddle** | Lake Oahe straddles CDT/MDT and the phone hops zones mid-trip. Everything orders off `timestamp_utc` and renders in **one zone (CDT default)**; use `--tz-offset -6` for Mountain. |
| **Source data is sacred** | **Never** edit `fishing-trip.xlsx` or the export CSVs. All tools *derive* alongside them. |

---

## 4. The web tools (what each command does)

| Command | Script | Output |
|---|---|---|
| `just replay <day>` | `replay_trip.py` + `replay_template.html` | self-contained `replay_<day>.html`: animated track + fish pins + Wrapped poster |
| `just analytics` | `build_analytics.py` | `analytics.html`: wt/inch by year + length/depth/time charts, filterable |
| `just areas` | `server.py` (`map-areas.html`) | polygon **area editor** → `areas/areas.geojson` |
| `just notes` | `server.py` (`notes.html`) | **trip-notes editor** → `exports/<year>/trip_notes.json` |

- `just areas` / `just notes` serve a **localhost-only** FastAPI app (atomic writes; never
  touches source CSV/xlsx). Default port **8765**.
- **Port taken?** Set a free one: `FISHING_PORT=8788 just areas` (or run uvicorn with a
  different `--port`).
- **Verify the Wrapped poster** (the harness can't reach the overlay):
  `node tests/shot_wrapped.js exports/2026/<day>/replay_<day>.html /tmp/wrapped.png`

---

## 5. Unfinished — APP-3 (iOS area auto-naming)

**Goal:** the phone reads `areas.geojson` and auto-fills `location_name` on catch save
(point-in-polygon), with **no server on the water**.

**Status: code DRAFTED + Core-tested, NOT on the phone yet.** The logic is in the repo and
`swift test` passes (36 tests), but it has **not** been added to the Xcode project, built, or
installed. What exists today:
- `app/FishingLoggerCore/Sources/FishingLoggerCore/AreaIndex.swift` — pure-Foundation GeoJSON
  parser + ray-casting point-in-polygon (`areaName(lat:lon:)`), Polygon + MultiPolygon, safe on
  missing/bad files. Covered by `app/FishingLoggerCore/Tests/.../AreaIndexTests.swift` (9 tests).
- `app/AppSources/areas.geojson` — the bundled copy of `areas/areas.geojson`.
- `Store.swift` loads it into `areaIndex` at launch; `CatchEntryView.swift` pre-fills an empty
  `location_name` from the frozen GPS fix (still user-editable).

**To finish next year (Xcode + device):**
  1. Add `AreaIndex.swift` to the Core group **and** `app/AppSources/areas.geojson` to the app
     target's **"Copy Bundle Resources"** in the Xcode project (synchronized folder group =
     dropping the `.swift` on disk auto-adds the code; the geojson must be added to the target).
  2. Re-`cp` the latest `app/AppSources/*.swift` + `areas.geojson` into the Xcode project, then
     build via the xcode MCP (FishingLogger has historically been tab **`windowtab2`**;
     re-list windows if it moved).
  3. Install to the phone (part of the pre-trip build in §1). Re-export `areas.geojson` from
     `just areas` first if you've edited the lake areas since.

Backlog detail: `docs/v2-roadmap.md` → **APP-3 / HAY-130**.

---

## 6. Where everything lives

| Thing | Path |
|---|---|
| Replay map | `replay_trip.py`, `replay_template.html` |
| Analytics | `build_analytics.py` → `analytics.html` |
| Authoring server | `server.py` + `map-areas.html` + `notes.html` |
| Command front-end | `justfile` |
| Replay-prep pipeline | `ingest.py`, `areas.py`, `replay_config.json` → `build/<trip>/replay_bundle.json` |
| Trip exports | `exports/2026/<YYYYMMDD>/*.csv` (durable, accumulating) |
| Historical seasons | `historical/{2023,2024,2025}/` (from `scripts/migrate_history.py`) |
| Named lake areas | `areas/areas.geojson` |
| Trip notes/review | `exports/<year>/trip_notes.json` |
| Weight model + history | `fishing-trip.xlsx`, `analysis.py` |
| iOS app source | `app/AppSources/` + `app/FishingLoggerCore/` (runnable project: private `iHusk/FishingLogger`) |
| Docs | `docs/` (methodology, replay-map-spec, xcode-mcp-workflow, app-build-plan, notes-schema, v2-roadmap) |
| Decisions | `docs/adr/` |
| Backlog | Linear project **Fishing Logger**, team **HAY** (`docs/v2-roadmap.md` maps issues → HAY IDs) |
