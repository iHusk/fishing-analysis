# Fishing Analysis — Data & Methodology

Durable reference for the `fishing-analysis` project. (Mirrors the assistant's working
memory so it survives across sessions.)

## Dataset

`fishing-trip.xlsx`, **Sheet1 only** (Sheet2/Sheet3 are ignored). Annual June walleye
fishing trips on **Lake Oahe, South Dakota** (inferred from spot names: Whitlock,
Cheyenne arm, Bob's, Pump House). Years 2023–2025. Only walleye are analyzed; a lone
perch is filtered out.

> ⚠️ The spreadsheet **schema changes between sessions** as data entry is made easier.
> Always re-inspect the actual columns before editing `analysis.py` / `analysis.ipynb`.

### Schema (as of 2026-06)

Per-fish records — **columns A:P** (read positionally; the right-side tables reuse header
names so name-based selection collides):

| Col | Field | Notes |
|-----|-------|-------|
| A | `id` | |
| B | `year` | |
| C | `fisherman` | |
| D | `day` | weekday name |
| E | `datetime` | catch timestamp |
| F | `fish_species` | walleye / perch |
| G | `kept` | all True currently |
| H | `length` | inches (total length) |
| I | `depth` | feet (stored positive; flipped negative for plotting) |
| J | `bait` | sparse |
| K | `weight_calc` | **legacy linear estimate — superseded, see below** |
| L | `location` | freeform spot name |
| M | `lure_color_1` | sparse (2025 only so far) |
| N | `lure_color_2` | sparse |
| O | `trip` | trip marker (June of each year) |
| P | `weigh_date` | **day the fish's bag was weighed at cleaning** |
| (opt) | `measured_wt_lbs` | **individual fish weight (lbs), app-populated**; enables the curve fit. Absent today. |

> **Loader contract:** columns are read **by name**, not position, because the layout
> changes often. pandas keeps the first occurrence of duplicated headers clean
> (`trip`, `weigh_date` = the per-fish columns) and suffixes the anchor-table copies
> (`trip.1`, `weigh_date.1`). The per-fish individual-weight column must be named
> `measured_wt_lbs` (a unique name). See `load_data()` in `analysis.py`.

Measured-weight **anchor tables** (to the right of the data — unique column names):

- **Daily weigh-ins** — `usecols='R:V'`, filter `daily_wt_per_inch.notna()`:
  `weigh_date, trip, daily_wt_lbs, day_inches, daily_wt_per_inch` (one row per weigh day).
- **Trip totals** — below the daily table: `trip, trip_wt_lbs, trip_inches, trip_wt_per_inch`.
- **Pooled** `avg wt/in` constant ≈ 0.0921 (the old linear fallback).

## Weight model

Fish weight scales with length **cubed**, not linearly, so the legacy constant
lb-per-inch (`weight_calc`, ≈0.0921 lb/in) over-weights small fish and badly
under-weights big ones (it capped a 21″ fish at ~2 lb).

**Model:** power law `W = a · L^b`.

- **Exponent `b` = 3.180** — published walleye standard-weight exponent
  (Murphy et al. 1990; Anderson & Neumann 1996). Lake Oahe, SD specifically:
  **b ≈ 3.061** (Carlander's Handbook). These are the "known knowns."
- **Coefficient `a` is calibrated per weigh-day** so each day's estimated weights sum
  exactly to the **measured `daily_wt_lbs`** (ground truth — the bag is weighed every
  day at cleaning). `a_day = daily_wt_lbs / Σ(Lᵇ over that day's fish)`. Days with no
  measured bag fall back to a pooled coefficient.

This keeps every day's total exactly right while distributing weight realistically
(per-fish range ~0.7–4.1 lb instead of the linear 1.2–2.1 lb).

**Relative weight (condition):** `Wr = 100 · W / Ws`, where the English-unit walleye
standard weight is `log10 Ws = -3.643 + 3.180·log10 L`. `Wr ≈ 100` = standard condition.
Mean Wr by year ≈ **88 (2023), 90 (2024), 107 (2025)** — 2025 fish were notably fatter.

### Why we don't fit `b` from our own data (yet)

A bag total only constrains the **sum** of fish weights, so for any `b` the per-day
coefficient can absorb the difference — `b` is **not identifiable** from bag weights.
Empirically, fitting `b` to the 6 measured daily bags gives **1.7–5.9** depending on
which days are included (vs. the physiological ~3.0–3.2), because year-to-year condition
and ±0.5 lb scale noise swamp the length signal.

**To fit our own curve we need individual fish weights.** Logging the weight of even a
sample of fish across the size range (e.g. via the planned phone app) lets us fit
`W = a·Lᵇ` directly by log-log regression. This path is **already implemented**:
`fit_length_weight()` runs an OLS fit on `log(measured_wt_lbs) ~ log(length)` and, once
at least `MIN_FIT_N` (=12) individual weights exist, its exponent **automatically
supersedes** the literature default — no code change needed. Per-day bag calibration of
`a` is still applied so totals stay exact. Until then, the literature `b` is used.

See **ADR 0001** (`docs/adr/0001-weight-curve-estimation.md`) for the decision record.

## Known data-quality issues

- **Net-tare (bag-weighing convention changed in 2026):** 2023–2025 daily bags were weighed
  **with the ~2 lb landing net on the scale**; 2026 onward is weighed **net-free**. Left
  uncorrected this overstates 2023–25 wt/inch and makes 2026 look worse than it was. The
  correction is **non-destructive** — source CSVs/xlsx are untouched; `analysis.py` carries
  `NET_TARE_LBS_BY_YEAR = {2023: 2.0, 2024: 2.0, 2025: 2.0}`, subtracted **per weigh session**
  from the bag before any measured/modeled wt/inch. Net-corrected wt/inch:
  2023≈0.075, 2024≈0.087, 2025≈0.088, **2026≈0.101** (2026 is the healthiest year on record).
- **Accumulating exports double-count:** the iOS app's dated export folders are supersets of
  prior days, so a weigh session (e.g. 2026-06-19) appears in *both* the 06-19 and 06-20
  folders. `load_history()` **dedups by catch** before any rollup — otherwise that session's
  fish (and bag) are counted twice (this was the original cause of a spuriously-low 2026
  modeled wt/inch). Run analysis off the LATEST folder; never `--all` across dated folders.
- **2026 `day_inches` derived, not exported:** the app exports `daily_wt_lbs` but leaves
  `day_inches` blank, so measured wt/inch (`bag ÷ day_inches`) is computed by summing the
  **kept-walleye** lengths per weigh session in the loader.
- **2024-06-15 weigh-day:** logged fish lengths sum to 240.75″ but the recorded
  `day_inches` is 250.75″ — a ~10″ discrepancy of **unknown cause** (a length typo on a
  logged fish, a wrong `day_inches` entry, or an unlogged fish are all possible). This
  does **not** affect weight estimates — those are calibrated to the measured bag
  *weight* (23.0 lb), not to `day_inches`. The notebook surfaces it only as a
  reconciliation check.

## Dev notes

- **Run Python via `uv`** — system python lacks plotly/duckdb; the notebook's original
  `pocs` pipenv env isn't on this machine. Examples:
  - `uv run --with plotly --with pandas --with openpyxl python script.py`
  - `uv run --with plotly --with pandas --with openpyxl --with duckdb --with nbconvert --with ipykernel jupyter nbconvert --to notebook --execute --inplace analysis.ipynb`
- `fishing-trip.png` is a single composite figure (the `cell-11` 2×2 dashboard), exported
  via kaleido at 1729×800. Not multi-page (PNG can't be).
