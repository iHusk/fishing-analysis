# Offline Fishing Logger — Build Plan (v1)

A pre-build planning doc. Captures the research, the locked decisions, the
architecture, and the open questions, so we think it through *before* writing code.
Companion to the user's research notes in `iphone-app.md` and the analysis pipeline
in `analysis.py` / `docs/methodology.md`.

## Goal

A personal iPhone app Tyler uses ~1 week/year on **Lake Oahe, SD** (no cell service) to:

1. Log every fish caught (length, depth, species, lure color, fisherman, **individual
   weight when weighed**) with auto-captured time + GPS.
2. Record the daily **bag weight** at cleaning (ground truth for the weight model).
3. Record the boat's **GPS travel track** for the day, with heading.
4. **Export** all of it, airtight, into the existing `fishing-trip.xlsx` / `analysis.py`
   pipeline.

It must be **fully offline**, **battery-survivable for a 10-hr day**, and **trustworthy
enough to replace pen-and-paper**.

## Locked decisions (2026-06-18)

| Decision | Choice | Implication |
|---|---|---|
| Framework | **Native SwiftUI + Core Location** | Best battery, most reliable offline GPS, bulletproof local storage. Claude writes the Swift; Tyler builds/runs in Xcode. |
| Apple account | **Free Apple ID** (with $99 fallback) | $0. Trip is **3 days** — inside the 7-day window. Build the morning of departure; complete the online trust+launch ritual (see checklist). If the free path shows any trouble in testing, **buy the $99 Developer Program and re-sign the app that same evening** — that removes the 7-day clock and the offline cert-trust risk entirely. |
| Map in v1 | **No basemap — cut** | Free tiles render near-empty for this reservoir; free satellite-offline is a licensing trap; the map pins GPS to full power. Defer an aerial basemap (USGS NAIP, self-packaged) to v2. |
| Full-day GPS track | **Keep in v1** | Tyler wants the "where we travelled all day" trail. Recorded via a hardened background session (see Red-team revisions), rendered as a polyline on a blank canvas + catch pins, exported as GPX. Not consumed by `analysis.py` but kept for personal review. |
| Users | **Whole boat** | Per-catch `fisherman` picker; app logs everyone's catches. Daily bag = whole boat's bag. |
| Location tagging | **Raw GPS + freeform text (v1)** | Auto-capture lat/lon per catch + an optional typed spot name. "Tap a named area" labeling deferred to v2. |
| Per-fish weight | **Not captured in v1** | Fish are measured (length) when caught; **only the bag is weighed, end of day**. So `measured_wt_lbs` stays optional/empty and the weight model keeps its per-day bag calibration. |

## Architecture

- **UI:** SwiftUI.
- **Location:** Core Location (`CLLocationManager`) with background mode.
- **Storage:** **GRDB.swift** over SQLite, in WAL mode, hardened for durability
  (`PRAGMA synchronous=FULL; PRAGMA fullfsync=ON;`). Plus a redundant append-only
  JSONL mirror.
- **Maps:** **MapLibre Native iOS** (`MLNOfflineStorage`) with OpenFreeMap / MapTiler
  vector tiles; download the Oahe region once on Wi-Fi (~10–50 MB).
- **Export:** Files-app visibility (`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`)
  + a share-sheet button (CSV/GPX, AirDrop/email).

## GPS strategy (battery vs. fidelity)

**Two-mode logging:**

- **Trail (continuous, background):**
  - `desiredAccuracy = kCLLocationAccuracyHundredMeters` (≈0.5–1%/hr; visually identical
    to "best" on a lake; also avoids iOS 16.4+ background suspension).
  - `distanceFilter = 15` m (drops wave/drift noise; ~breadcrumb every 50 ft).
  - `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`
    (never silently stop while anchored), `activityType = .otherNavigation`,
    `showsBackgroundLocationIndicator = true`.
  - Write **each fix to disk immediately** in the delegate callback.
- **Fish tag (on-demand, best accuracy):** when "Log Catch" is pressed, fire a one-shot
  `requestLocation()` at `.bestForNavigation`, take the first fix with
  `horizontalAccuracy < 10`, then revert. High-accuracy pin without paying for it all day.

**Heading:** log both — `CLLocation.course` while moving (`speed > ~0.5 m/s`,
free), and `CLHeading.magneticHeading` when stopped (cheap; filter readings with
`headingAccuracy > 10°` to reject motor/electronics interference).

**Offline cold-start:** open the app at the marina (in cell range) to warm the GPS
before launching; the fix then holds all day offline.

**Battery reality:** even optimized, a 10-hr day is a lot. Plan around a **power bank**
clipped in the boat; surface a warning when `ProcessInfo.isLowPowerModeEnabled` is true
(Low Power Mode throttles location updates). Airplane-mode + Location-on is the best
battery posture offline.

## Data integrity ("airtight")

**The one rule: never hold a record only in memory.** iOS can kill a backgrounded app
with ~200 ms notice and no reliable callback. So:

- Every "Save Fish" tap completes a synchronous disk write **before** the UI shows
  "Saved ✓". The confirmation *is* the acknowledgment of a committed write.
- **GRDB + SQLite, WAL, `synchronous=FULL`, `fullfsync=ON`** — survives crash, OOM-kill,
  force-quit, reboot, battery death. (Apple's default fsync is *not* crash-safe; this
  fixes it.)
- **Redundant mirror:** append one JSONL line per record to a second file — a partial
  write corrupts at most its own last line, never earlier records.
- **Always-current export file:** continuously (re)write
  `/Documents/fishing-trip-YYYY-MM-DD.csv` after every insert, visible in the Files app —
  so the data is retrievable even if the app later won't launch.

**Trust UX (beats paper):** persistent "Fish logged: N" counter, per-entry confirmation
with the saved values, last-saved indicator, scrollable + editable day-log, end-of-day
summary, and an export dialog that reports the **record count** so nothing is silently
lost.

## Offline maps

- MapLibre Native iOS with `MLNOfflineStorage` offline regions.
- Pre-download the Oahe bounding box (z8–z16) once on Wi-Fi before the trip; persists in
  Application Support (iOS won't evict it).
- Render the live track as a polyline + catch/waypoint pins on top.
- Bathymetry/depth charts: **not v1** (onX Fish / Navionics already do this well if Tyler
  wants a reference). Our value is *his* track + *his* catch data.

## Screens (v1)

1. **On-water / "Now":** full-screen offline map, live track polyline, current-position
   heading arrow, big **"Log Catch Here"** button (2-sec hold or double-tap to prevent
   accidental presses on a bouncing boat), persistent catch counter, sunrise/sunset.
2. **Log Catch sheet** (everything captured *at the catch*): auto GPS + time + heading;
   quick **fisherman** picker (whole-boat), species (default walleye), **length** stepper
   (large +/− buttons, last-value default), **depth** (positive feet), optional lure
   color(s), optional freeform **location** name. No per-fish weight (bag-only, see below).
3. **Daily weigh-in:** once/day at cleaning — `weigh_date`, `trip`, `daily_wt_lbs`, and
   `day_inches` (or auto-summed from the day's catches). **This is the only weight captured.**
4. **Day log:** scrollable, editable list of today's catches + waypoints.
5. **Export:** writes catches CSV + daily-weights CSV + track GPX/CSV; share-sheet /
   AirDrop with record counts.

**On-water UX rules:** high-contrast light theme (sunlight), ≥60 pt tap targets
(wet/gloved hands), steppers not keyboards, primary actions in the thumb-reachable bottom
third, haptics on every save.

## Data model & pipeline round-trip

Exports are flat CSVs whose **column names** match the pipeline (the loader reads by name;
order is cosmetic). Extra app-only columns ride along harmlessly (`load_data()`
sub-selects `PERFISH_COLS`).

**Catches CSV** — `PERFISH_COLS` names + new fields:
```
id, year, fisherman, day, datetime, fish_species, kept, length, depth,
bait, weight_calc, location, lure_color_1, lure_color_2, trip, weigh_date,
measured_wt_lbs, gps_lat, gps_lon, gps_accuracy_m, gps_heading, gps_altitude_m,
app_uuid, device_ts_utc
```
- `depth` stored **positive** feet (loader flips sign).
- `datetime` = local wall-clock (drives hour-of-day analysis); `device_ts_utc` = UTC audit.
- `weight_calc` left blank (legacy/superseded).
- `app_uuid` = the app's real identity key (offline-safe, dedup on re-import).

**Daily-weights CSV** (→ anchor table `*.1` headers when placed in Sheet1):
```
weigh_date, trip, daily_wt_lbs, day_inches, daily_wt_per_inch
```
- Must emit `daily_wt_per_inch` — the loader filters anchor rows on `.notna()` of it.

**Track:** `track.gpx` (primary, universal) + `track.csv` fallback
(`timestamp, lat, lon, accuracy_m, altitude_m, speed_mps, course_deg, track_id, trip`).

**Auto-assignment:** `app_uuid` always app-owned; integer `id` left blank and filled at
merge (`max(id)+row#`); `year` from datetime; `trip` = the session's June marker;
`weigh_date` = the active fishing day; `day` = weekday name.

**`measured_wt_lbs` stays empty in v1** (only the daily bag is weighed). The column and the
fit path remain in place so that *if* Tyler ever decides to weigh a sample of individual
fish, ≥12 across the size range would auto-switch the curve from the literature exponent to
a fitted one (`fit_length_weight()`) — but v1 imposes no such burden. The weight model runs
purely on **per-day bag calibration**, exactly as it does today.

## ⚠️ Risk: free Apple ID + "airtight" are in tension

The free account's provisioning profile **expires after 7 days** — the app then refuses to
launch until rebuilt/reinstalled from the Mac. Mitigations baked into the plan:

- **Re-sideloading the same bundle ID preserves the data container** — data is NOT lost on
  reinstall (as long as the app isn't *deleted*).
- **Build & install right before leaving.** If the trip exceeds 7 days, bring the laptop to
  rebuild, or reconsider the $99 account (1-yr profiles).
- **Export every evening** (AirDrop/email the CSV when back at the cabin / in service) so no
  single failure costs more than one day.
- **Keep iCloud Backup on** (auto when charging + on Wi-Fi + locked) as an off-device safety
  net for the app container.
- The always-present Files-app CSV means data is recoverable even if the app won't open.

> If the 7-day dance proves annoying in testing, the $99 account is the clean fix — flag it
> then.

## v1 scope vs. deferred

**v1:** offline map + live track + heading, whole-boat catch logging, daily weigh-in,
airtight local storage + redundant mirror, CSV/GPX export, sunrise/sunset, on-water UX.

**Defer (v2+):** solunar times, historical xlsx import into the app, multi-year
spot heatmaps, Apple Watch companion, voice entry (offline reliability too low),
Bluetooth fish-finder depth, bathymetric charts.

**Never:** community/social, weather/wind (needs network), cloud lock-in.

## Open decisions still needed (data-model level)

- ~~**GPS vs. named `location`.**~~ **Resolved:** raw GPS + freeform text in v1; named-area
  labeling is v2.
- ~~**`measured_wt_lbs` sampling.**~~ **Resolved:** not captured — bag-only weighing; field
  stays optional/empty.

Still open:

1. **`weigh_date` handling.** If the bag is cleaned the next morning, do we let one
   per-day `weigh_date` apply to all that day's catches?
2. **`day_inches` source.** Still measure total bag inches at cleaning (keeps the
   independent reconciliation check that flagged 2024-06-15), or auto-sum the day's logged
   catch lengths (guarantees the anchor row survives the loader filter, but loses the
   cross-check)?
3. **Merge workflow.** Keep hand-editing `fishing-trip.xlsx` and paste app CSVs in, or
   write a small `CSV → xlsx` merge script?

## Red-team revisions (2026-06-18)

Four adversarial agents stress-tested this plan against current iOS facts. Key changes
folded in:

**Critical data-integrity fixes (non-negotiable):**
- **File protection:** set `NSFileProtectionCompleteUntilFirstUserAuthentication` on the
  SQLite DB **and its `-wal`/`-shm` sidecars**, the CSV, and any mirror. The iOS default
  (`NSFileProtectionComplete`) makes files **unwritable while the phone is locked** — the
  all-day-in-pocket condition — and would silently drop writes. **Field-test a
  locked-pocket drive.**
- **iCloud backup is NOT a recovery path** for a sideloaded app (no App Store source to
  reinstall from on restore → data never reattached). **Daily off-device export is the
  only real backup.** Reframe the Risk section accordingly; add a "haven't exported today"
  nag.
- **Durable writes without UI freeze:** GRDB `DatabasePool.asyncWrite`; show "Saved ✓"
  **only from the post-commit completion** (that completion *is* the durability barrier).
  Never run `fullfsync` on the main thread.
- **Atomic file writes:** write the CSV/exports via `Data.write(.atomic)` (temp + rename),
  never truncate-in-place; don't rewrite the whole CSV on every insert (only at natural
  checkpoints). Verify export record-count/checksum before presenting the share sheet.
- **Soften the durability claim:** WAL + `synchronous=FULL` + `fullfsync=ON` gives *no
  corruption* and survives crash/kill/reboot; the single most-recent record can still be
  lost only on an instantaneous power-cut.
- **Drop the separate JSONL mirror** — the always-current atomic CSV is already an
  independent second copy *and* the recovery artifact; a third hand-rolled log is more to
  test for little gain.

**Core Location fixes (if GPS stays in v1):**
- **Two `CLLocationManager` instances:** one coarse/continuous (trail), one on-demand
  high-accuracy (catch fix). `requestLocation()` over a live continuous stream silently
  no-ops → precise pins would degrade to coarse. Time-box the precise fix; **never block
  "Save Fish"** on it (log with best-available accuracy, upgrade async).
- If a **background** track is kept: hold a `CLBackgroundActivitySession` (iOS 17+) for the
  session — *this*, not the accuracy constant, is what keeps WhenInUse logging alive when
  locked. Add a visible "TRACK PAUSED" watchdog so gaps are never silent.
- Correct the false claims: accuracy constant does **not** govern background suspension;
  "marina warm-up holds all day" is false (ephemeris ~2–4 hr; any loss-of-lock offline
  costs 20 s–3 min to re-fix). Keep GPS running with clear sky view; heading on a metal
  boat is best-effort/often-null — store it flagged, don't trust it.

**Field-workflow fixes:**
- **`weigh_date` = explicit fishing-session key** stamped on both the bag and that session's
  catches — decoupled from clock midnight. Next-morning cleaning otherwise mis-calibrates
  both days silently. Keep measured `day_inches` independently + auto-sum cross-check warning.
- **One-tap catch entry:** big bottom-third LOG → instant write with **all fields carried
  forward** (fisherman buttons, species=`walleye`, last length/depth/lure) → inline length
  adjust → **Undo toast** (drop the 2-sec hold). Editable `datetime` + "released" toggle in
  the day-log (back-dating & corrections are first-class).
- **Pipeline — schema is NOT frozen (2026-06-18):** Tyler confirmed we may change the data
  schema to fit the app, as long as `fishing-trip.xlsx` is preserved as the **historical
  record** and any change is **reviewed first**. So we drop the brittle `.1`-suffix
  co-location hack entirely. New design:
  - **Freeze `fishing-trip.xlsx`** (2023–2025) as the archived source-of-record; stop
    appending to its awkward Sheet1 layout.
  - **Clean go-forward schema:** the app writes plain, separately-named CSVs —
    `catches.csv`, `daily_weights.csv`, `track.(csv|gpx)` — no duplicate headers; use an
    explicit `weigh_session_id` key (not an overloaded date); compute `daily_wt_per_inch`;
    `app_uuid` as the dedup key; `fish_species` lowercase; positive `depth`; timezone-free
    local `datetime`.
  - **Update `load_data()`** to read the clean schema (separate sheets/CSVs), not the R:V
    co-located block. Optionally **one-time migrate** the 3 historical years into the clean
    store, asserting every per-day and per-year bag total is unchanged.
  - **Propose the exact clean schema for Tyler's review BEFORE editing `analysis.py`.**
    Verify end-to-end by running `analysis.py` on migrated + app data (per-day `a` calibrates,
    totals match).

**Scope decisions — RESOLVED (2026-06-18):**
1. **Offline MapLibre basemap → CUT from v1.** (Red-team agreed.) No basemap; the track
   renders on a blank canvas with catch pins. Aerial basemap (USGS NAIP MBTiles) is a v2
   option.
2. **Full-day background track → KEPT in v1** (Tyler's call — he wants the day's trail).
   Therefore the background-location hardening above is **mandatory**: `CLBackgroundActivitySession`,
   `NSFileProtectionCompleteUntilFirstUserAuthentication` on all DB/track files, the
   "TRACK PAUSED" watchdog, two-manager GPS, and a power bank are required, not optional.
   Because the track is the biggest risk/battery sink, **build it AFTER the airtight
   catch+bag core is proven** so the core ships even if the track needs more time.
3. **Account → stay FREE, with a same-evening $99 re-sign as the fallback.** Run the strict
   pre-trip checklist; if anything flakes in testing, buy the Developer Program and re-sign
   that evening (removes the 7-day clock + offline cert-trust risk). Mandatory backstops
   regardless: always-present Files-app CSV, paper for the daily bag weight, MacBook along.

## Pre-trip checklist (free profile — do in order, WHILE IN SERVICE)

1. **Build & install the morning of departure** (resets the 7-day clock → ~4 days margin).
   Freeze the bundle ID early; don't spin up new App IDs in the final week (10-per-7-days cap).
2. **Trust the cert online:** Settings → General → VPN & Device Management → tap developer →
   **Verify/Trust**; confirm "Verified."
3. **Launch the app to its main screen with NO prompts while still online** (caches trust).
4. Grant **Location: Always** + Precise. Turn **off Low Power Mode** (and iOS 26 Adaptive
   Power — auto-enables LPM at 20%, which throttles background location). Background App
   Refresh **on** for the app.
5. **Warm GPS** before leaving cell range. **Dry run:** log a test catch → "Saved ✓" + CSV
   appears → force-quit → reopen → record survived → **export one CSV** to verify the
   round-trip. **Reboot the phone in service and relaunch** (confirms no verify-prompt after
   a lakeside reboot).
6. Keep the phone on the **power bank** (stay >20%). Bring the **MacBook + cable** as the
   break-glass rebuild, and **paper for the daily bag weight** (the one number that can't be
   re-derived).

## Final data schema (LOCKED 2026-06-18)

Three flat CSVs the app writes to its own sandbox (Excel file untouched). Schema is not
frozen — loader reads by name, so columns can be added later without breaking anything.

**`catches.csv`** (one row per fish):
```
id, uuid, timestamp_local, timestamp_utc, year, weigh_session_id, trip, fisherman,
species, kept, length_in, depth_ft, water_temp_f, lure_color1, lure_color2, bait,
location_name, lat, lon, gps_accuracy_m, heading_deg, notes
```
- `id` = running int per device (matches the legacy `id`); `uuid` = stable identity/dedup key.
- `water_temp_f` = carry-forward (set once per spot, stamps each catch).
- `kept` drives bag-calibration filtering (released fish excluded from the denominator).

**`daily_weights.csv`** (one row per weigh session = ground-truth bag):
```
weigh_session_id, weigh_date, trip, daily_wt_lbs, day_inches, daily_wt_per_inch,
n_catches_logged, notes
```

**`track.csv`** (append-only, one row per GPS fix):
```
timestamp_utc, timestamp_local, trip, weigh_session_id, lat, lon, accuracy_m,
altitude_m, speed_mps, course_deg
```

**Capture decisions (2026-06-18):** added `water_temp_f` only. Declined for v1 (can add
later, schema-compatible): structure_type, presentation, release_condition chips; CPUE
Lines-In/Out + angler count; photo. Compute-later (no capture): moon/solunar, sunrise
offset, trolling speed, dwell/spot-naming (from track); weather/pressure (backfill from KPIR
Pierre by date).

**Post-trip loader work (reviewed change to `load_data()`):** read the two CSVs; rename
`length_in→length`, `depth_ft→depth`, `species→fish_species`, `timestamp_local→datetime`
(parse it), `location_name→location`, `lure_color1/2→lure_color_1/2`; derive `day` weekday;
drop legacy `weight_calc`; group calibration by `weigh_session_id`; **exclude `kept==false`
from the calibration denominator**; filter anchor rows on `daily_wt_lbs.notna()` (not
`daily_wt_per_inch`). Migrate the 3 historical years with totals asserted unchanged (per-day
bags, per-year counts, Wr ≈ 88/90/107); historical rows carry blank GPS/uuid (synthesize
integer `id` and `weigh_session_id = "hist-<date>"`).

## Rough build sequence

1. Xcode project, Info.plist location keys + background mode, free-account signing to device.
2. GRDB schema + hardened PRAGMAs + the "save = committed write" pattern; catch entry +
   day-log + counter. **(Airtight core first — validate it before anything pretty.)**
3. Core Location: background trail logging + on-demand best-fix tagging + heading.
4. CSV/GPX export + Files-app visibility + share sheet; verify a round-trip into
   `analysis.py`.
5. MapLibre offline region + live track polyline + pins.
6. Daily weigh-in screen; on-water UX polish (contrast, tap targets, haptics).
7. Field-test checklist (cold-start fix, 10-hr battery w/ power bank, kill-app data survival,
   export verification).
