# DATA-1 — Historical Migration Design (HAY-120)

**Status:** DESIGN ONLY. No implementation. `fishing-trip.xlsx` is the sacred historical
source-of-record and is **never written** by this migration. All inspection below was done
read-only.

**Goal:** Project the 3 historical years (2023–2025) out of the legacy `fishing-trip.xlsx`
Sheet1 layout into the LOCKED go-forward CSV schema (`catches.csv` + `daily_weights.csv`,
per `docs/app-build-plan.md`), so WEB-1 (HAY-125) can compute its two analytics metrics over
**all** years from one uniform store — without touching the xlsx.

---

## 1. Actual xlsx layout (what's really there)

**Workbook:** `Sheet1`, `Sheet2`, `Sheet3`. Only **Sheet1** carries data (Sheet2/Sheet3 empty
and ignored, consistent with `docs/methodology.md`).

**Sheet1** is `75 rows × 22 columns`, a single sheet holding **three co-located tables**
separated by a blank spacer column (col 16 / Excel `Q`):

### 1a. Per-fish block — cols A:P (0–15), one row per fish
Header in row 0; **74 data rows**. Columns (read by name in `load_data()` because order drifts):

`id, year, fisherman, day, datetime, fish_species, kept, length, depth, bait, weight_calc,
location, lure_color_1, lure_color_2, trip, weigh_date`

Species: **73 walleye + 1 perch** (the perch is filtered out by the pipeline).

| year | walleye rows | with usable `length` (>0) |
|------|--------------|----------------------------|
| 2023 | 32 | 32 |
| 2024 | 30 | 30 |
| 2025 | 11 | 11 |
| **total** | **73** | **73 (100%)** |

Field fill (walleye, /73): `fisherman` 73, `depth` 73, `datetime` 73, `kept` 73 (all `True`),
`weigh_date` 73, `trip` 73, `location` 57, `bait` 57, `lure_color_1` 11 (2025 only),
`lure_color_2` 5. Distinct fishermen: `brent, brian, matt, tyler`. **No lat/lon/GPS columns
exist anywhere.**

### 1b. Daily weigh-in anchor table — cols R:V (17–21), rows 1–6
Header row 0 (these are the duplicate names pandas suffixes `weigh_date.1`, `trip.1`):
`weigh_date, trip, daily_wt_lbs, day_inches, daily_wt_per_inch` — **6 weigh-day rows**:

| weigh_date | trip | daily_wt_lbs | day_inches | daily_wt_per_inch |
|---|---|---|---|---|
| 2023-06-15 | 2023-06 | 21.2 | 246.5 | 0.08600 |
| 2023-06-17 | 2023-06 | 20.1 | 252.25 | 0.07968 |
| 2024-06-14 | 2024-06 | 25.0 | 255.75 | 0.09775 |
| 2024-06-15 | 2024-06 | 23.0 | 250.75 | 0.09172 |
| 2025-06-13 | 2025-06 | 9.32 | 80.75 | 0.11542 |
| 2025-06-14 | 2025-06 | 10.17 | 95.0 | 0.10705 |

### 1c. Trip-totals block — same cols, rows 9–12 (below the daily table)
Header `trip, trip_wt_lbs, trip_inches, trip_wt_per_inch` — **3 trip rows**:

| trip | trip_wt_lbs | trip_inches | trip_wt_per_inch |
|---|---|---|---|
| 2023-06 | 41.3 | 498.75 | 0.08281 |
| 2024-06 | 48.0 | 506.5 | 0.09477 |
| 2025-06 | 19.49 | 175.75 | 0.11090 |

### 1d. Pooled fallback constant — row 15
`pooled avg wt/in (fallback) = 0.09212` (the legacy linear constant; not migrated as data).

**There are no per-catch weights** (`measured_wt_lbs` absent entirely) and **no per-catch
GPS** in any historical year.

---

## 2. Field-by-field mapping: OLD xlsx → NEW schema

### catches.csv (target header)
`id, uuid, timestamp_local, timestamp_utc, year, weigh_session_id, trip, fisherman, species,
kept, length_in, depth_ft, water_temp_f, lure_color1, lure_color2, bait, location_name, lat,
lon, gps_accuracy_m, heading_deg, measured_wt_lbs, notes`

> **Schema evolution (2026-06):** `measured_wt_lbs` was added (inserted **before** `notes`, so
> `notes` stays the free-text final column). It is **blank in all historical + pre-2026 rows**.
> Readers MUST key by header name, not column position — old files have one fewer column and
> `notes` one slot earlier. See `app/FishingLoggerCore/.../Schema.swift`.

| NEW field | OLD source | Transform / synthesis |
|---|---|---|
| `id` | `id` | Carry through as-is (running int already exists historically). |
| `uuid` | — (none) | **Synthesize** deterministic UUID, e.g. `uuid5(NS, f"hist-{year}-{id}")`, so re-runs are stable and dedup-safe. |
| `timestamp_local` | `datetime` | Direct (already local wall-clock; drives hour-of-day). |
| `timestamp_utc` | — (none) | **Leave blank.** No tz historically; do NOT fabricate (would be a false audit value). Optionally derive `datetime + 6h` (US/Central CDT) but recommend blank + note. |
| `year` | `year` | Direct. |
| `weigh_session_id` | `weigh_date` | **Synthesize** `"hist-<weigh_date:YYYY-MM-DD>"` (per app-build-plan note). This is the calibration grouping key. |
| `trip` | `trip` | Normalize to the app's `YYYY-MM` form (`2023-06-01` → `2023-06`). |
| `fisherman` | `fisherman` | Direct. Historically **always present** (no per-catch gap — unlike the general "fisherman-per-catch may be missing" worry). Title-case to match app (`brent`→`Brent`) optional/cosmetic. |
| `species` | `fish_species` | Direct, lowercase (already lowercase). Migrate all rows incl. the 1 perch; pipeline filters species itself. |
| `kept` | `kept` | Direct (all historical = `True`). Drives bag-calibration denominator. |
| `length_in` | `length` | Direct (inches). **100% populated** — see §3. |
| `depth_ft` | `depth` | Direct, **stored positive** (loader flips sign). 100% populated. |
| `water_temp_f` | — (none) | **Leave blank** (not captured pre-app). |
| `lure_color1` | `lure_color_1` | Direct (sparse: 2025 only, 11 rows). |
| `lure_color2` | `lure_color_2` | Direct (sparse, 5 rows). |
| `bait` | `bait` | Direct (57/73). |
| `location_name` | `location` | Direct (57/73 freeform spot names). |
| `lat` | — (none) | **Blank.** No historical GPS. |
| `lon` | — (none) | **Blank.** |
| `gps_accuracy_m` | — (none) | **Blank.** |
| `heading_deg` | — (none) | **Blank.** |
| `measured_wt_lbs` | — (none) | **Blank** historically (per-catch weighing started with the app, 2026-06). Distinct from the dropped computed `weight_calc`; this is ground-truth measured weight for length→weight calibration. |
| `notes` | — (none) | **Blank** (or a migration provenance tag like `"migrated:xlsx-Sheet1"`). |

Dropped legacy field: `weight_calc` (superseded linear estimate — not carried; `day` weekday
is re-derivable from `datetime`, so optional to migrate).

### daily_weights.csv (target header)
`weigh_session_id, weigh_date, trip, daily_wt_lbs, day_inches, daily_wt_per_inch,
n_catches_logged, notes`

| NEW field | OLD source | Transform / synthesis |
|---|---|---|
| `weigh_session_id` | `weigh_date` (R:V) | `"hist-<YYYY-MM-DD>"` — must match the catches join key exactly. |
| `weigh_date` | `weigh_date` (R:V) | Direct. |
| `trip` | `trip` (R:V) | Normalize to `YYYY-MM`. |
| `daily_wt_lbs` | `daily_wt_lbs` | Direct — **ground truth bag**, the anchor for per-day `a` calibration. |
| `day_inches` | `day_inches` | Direct (independent measured bag inches; preserves the reconciliation cross-check). |
| `daily_wt_per_inch` | `daily_wt_per_inch` | Direct (already a column — **this IS the headline metric**, §4a). |
| `n_catches_logged` | derived | Count of migrated catches sharing the session (see §5 — matches exactly except 2024-06-15). |
| `notes` | — | Blank, or carry the 2024-06-15 discrepancy note. |

**Loader-filter caveat:** today's `load_data()` filters anchor rows on `daily_wt_per_inch.notna()`;
the app-build-plan's reviewed change filters on `daily_wt_lbs.notna()`. Historically **both are
fully populated**, so either filter yields all 6 rows — migration is safe under both. The 6
trip-total rows (§1c) are **not** emitted as `daily_weights` rows; they are reconstructable by
summing daily rows per trip (verified §5) and are only used as reconciliation targets.

**Fields that DON'T exist historically (summary):** `uuid`, `timestamp_utc`, `water_temp_f`,
`lat`, `lon`, `gps_accuracy_m`, `heading_deg`, `measured_wt_lbs` (per-catch weight). Synthesize
only the join/identity keys (`uuid`, `weigh_session_id`); **leave all sensor/GPS/temp fields
blank** — never fabricate measured values.

---

## 3. Per-catch LENGTH availability per year (gates the modeled wt/inch chart)

This is the good news that unlocks WEB-1's secondary metric:

| year | walleye | with usable `length_in` | coverage |
|------|---------|--------------------------|----------|
| 2023 | 32 | 32 | 100% |
| 2024 | 30 | 30 | 100% |
| 2025 | 11 | 11 | 100% |

**Every historical walleye has a length.** The modeled per-catch wt/inch chart is feasible for
all three years with no imputation. (Depth is also 100% populated, so depth-vs-length views work
historically too.)

---

## 4. The two analytics metrics WEB-1 (HAY-125) needs

### 4a. HEADLINE — MEASURED daily/trip wt-per-inch, aggregated by year
**Source:** already-computed columns. `daily_wt_per_inch` (6 daily rows) and `trip_wt_per_inch`
(3 trip rows) come straight from the bag scale ÷ measured inches — **no model involved.**

- Per-trip (= per-year here, one trip/year): **2023 = 0.0828, 2024 = 0.0948, 2025 = 0.1109**
  lb/in. Monotonic upward trend (fish getting heavier per inch — consistent with the rising
  mean relative-weight 88→90→107 in methodology).
- Per-weigh-day available too (2 days/year) if WEB-1 wants finer granularity.

**Feasibility: trivially feasible, all years, exact.** It is measured ground truth, identical
whether read from xlsx or migrated CSV. Recommend WEB-1 aggregate by `trip`/`year` from the
daily rows (or read the trip block) — no power curve needed.

### 4b. SECONDARY — MODELED per-catch wt/inch via the existing power curve
**Source:** `estimate_weights()` in `analysis.py`. `weight_est = a_day · length^b`; per-catch
wt/inch = `weight_est / length`. `a_day` is calibrated so each session's estimates sum exactly
to `daily_wt_lbs`; `b = 3.180` literature (auto-fitted only once ≥12 individual weights exist —
which never happens historically, since `measured_wt_lbs` is absent).

- **Feasible for all 3 years** because (i) every catch has a length and (ii) every catch maps to
  a weigh session with a measured bag, so every day gets a real calibrated `a_day` (no pooled
  fallback needed historically).
- **Limits to state plainly:**
  1. `b` is **not** fitted from our data (bag totals can't identify `b`; see methodology). It is
     the literature 3.180. The per-catch *split* depends on this assumption.
  2. The metric is a **modeled distribution of a measured total** — its per-year *sum* exactly
     equals the measured bag (that's the calibration), so the secondary chart's aggregate
     reconciles with the headline by construction. Only the per-fish spread is modeled.
  3. 2025 has only 11 fish across 2 days — small-n; per-catch spread is noisier.
  4. `kept` is all-True historically, so the released-fish exclusion is a no-op for these years
     (it will matter for app-era data).

---

## 5. Reconciliation checks + non-destructive output location

### Reconciliation (migrated data must reproduce xlsx within tolerance)
All verified read-only during this design; the migration script should **assert** them:

**A. Per-year walleye counts** — migrated catch count per year == `{2023:32, 2024:30, 2025:11}`.

**B. Bag weights** — Σ `daily_wt_lbs` per trip == `trip_wt_lbs`:
`2023: 21.2+20.1 = 41.3 ✓`, `2024: 25+23 = 48.0 ✓`, `2025: 9.32+10.17 = 19.49 ✓`.

**C. Per-session catch count** (`n_catches_logged`) vs logged fish:
2023-06-15 n=16, 2023-06-17 n=16, 2024-06-14 n=15, 2024-06-15 n=15, 2025-06-13 n=5,
2025-06-14 n=6 — all consistent.

**D. Length-sum cross-check** (Σ logged `length` per session vs measured `day_inches`):
matches **exactly for 5 of 6 sessions**. The **known** discrepancy persists at **2024-06-15:
logged 240.75″ vs recorded `day_inches` 250.75″ (~10″ gap, unknown cause)** — documented in
methodology. This does **not** affect weight estimates (those calibrate to the 23.0 lb *bag*,
not to inches). The migration must **preserve `day_inches` as-recorded** (250.75) and surface
this as a warning, not silently "fix" it. Tolerance for the other checks: exact (bag weights /
counts), so use `==` with float epsilon on weights.

**E. Post-migration end-to-end:** run `analysis.py` over the migrated store and assert per-year
`total_weight_lbs` and mean `rel_weight` reproduce ≈ 88/90/107 — i.e. the curve calibrates and
totals stay exact.

### Output location (xlsx stays untouched)
Mirror the existing app-export tree, which already partitions by year/date under
`exports/<year>/<YYYYMMDD>/`. Two clean options:

- **Recommended:** a sibling `historical/` root holding one folder per migrated year, e.g.
  `historical/2023/catches.csv` + `historical/2023/daily_weights.csv` (and `2024/`, `2025/`).
  Clearly labels provenance ("derived from frozen xlsx"), keeps app exports and migration
  outputs from intermingling, and lets the loader simply glob `historical/**` + `exports/**`.
- **Alternative:** write per-year into the existing `exports/<year>/` convention (e.g.
  `exports/2023/migrated/`) so there is a single uniform tree. Slightly muddier provenance.

Either way: **new files only**, `fishing-trip.xlsx` is read-only input and is never modified.

---

## Summary for the human — mapping + surprises/risks

- **Layout confirmed:** one Sheet1, three co-located tables (per-fish A:P, daily anchor R:V rows
  1–6, trip totals rows 9–12, pooled constant row 15). 73 walleye + 1 perch; 6 weigh-days; 3
  trips. No GPS, no per-catch weights, ever.
- **Best surprise:** **length coverage is 100%** for all years (32/30/11). The modeled per-catch
  wt/inch chart (WEB-1 secondary) is fully feasible historically with zero imputation. Likewise
  `fisherman` and `depth` are 100% present — the feared "fisherman-per-catch missing" gap does
  **not** exist in the historical data.
- **Headline metric is free:** `daily_wt_per_inch` / `trip_wt_per_inch` already exist as measured
  columns (0.083 → 0.095 → 0.111 by year). No model required.
- **Blank-by-design fields:** `uuid` (synthesize deterministic), `weigh_session_id` (synthesize
  `hist-<date>`), `timestamp_utc` / `lat` / `lon` / `gps_accuracy_m` / `heading_deg` /
  `water_temp_f` / `measured_wt_lbs` — all blank; do not fabricate.
- **Risk 1 — `b` is assumed, not fitted.** The secondary metric's per-fish spread rides on the
  literature exponent 3.180 (bag totals can't identify `b`). Aggregates still reconcile exactly;
  only the per-catch distribution is modeled. Flag this in the WEB-1 UI.
- **Risk 2 — 2024-06-15 inch discrepancy (240.75 logged vs 250.75 recorded).** Migrate
  `day_inches` as-recorded and warn; never auto-correct. Weight estimates are unaffected.
- **Risk 3 — loader filter mismatch.** Current `load_data()` filters anchor rows on
  `daily_wt_per_inch.notna()`; the reviewed go-forward change uses `daily_wt_lbs.notna()`. Both
  are fully populated historically, so migration is safe either way — but the loader rewrite (DATA
  follow-up) should standardize on `daily_wt_lbs.notna()`.
- **Risk 4 — small-n 2025** (11 fish / 2 days): per-catch secondary chart is noisier; headline is
  fine.
- **Output:** propose `historical/<year>/{catches,daily_weights}.csv` (recommended) or
  `exports/<year>/migrated/`. xlsx is read-only and untouched throughout.
