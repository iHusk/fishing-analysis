# ADR 0003 — Non-destructive data corrections

- **Status:** Accepted
- **Date:** 2026-06-21
- **Deciders:** Tyler (project owner)

## Context

The raw inputs — `fishing-trip.xlsx` and the app's `exports/**/*.csv` — are the
**single, sacred source of truth**. But the raw data is not analysis-ready as logged:

- In **2023–2025** the daily bag was weighed **with the net on the scale**, so each
  recorded `daily_wt_lbs` is heavy by a fixed net tare.
- The app **accumulates** its exports, so re-exporting a day yields **overlapping rows**
  that would double-count if loaded naively.
- Some 2026 weigh-sessions were logged with a measured bag weight but a **blank
  `day_inches`**, leaving the per-inch metric undefined.
- Older years had to be **moved** into a normalized per-year layout.

We want every one of these fixes without ever **editing the source files**, which would
be irreversible and would destroy the audit trail.

## Decision

**Source data is immutable.** All corrections live in the **loader / config** and
**derive** new values; they never mutate `fishing-trip.xlsx` or the CSV exports:

1. **Net-tare correction.** `analysis.py` defines `NET_TARE_LBS_BY_YEAR =
   {2023: 2.0, 2024: 2.0, 2025: 2.0}` and subtracts it per weigh-session
   (clamped `>= 0`) before recomputing weight-per-inch. It is **inert by default**
   (empty map ⇒ no change).
2. **Accumulating-export dedup.** `load_history()` drops duplicate rows on
   `(weigh_session_id, id, timestamp_local)` so re-exported days collapse to one copy.
3. **Derived `day_inches`.** Where `day_inches` is blank, it is **derived from the
   kept-walleye length sum** for that session; rows carrying a real value are left
   untouched.
4. **Historical migration.** Older years live under `historical/<year>/`, which
   `load_history()` reads alongside `exports/2026/**` into one frame.

The source files stay byte-for-byte as logged; the corrected frame exists only in
memory / in derived outputs.

## Consequences

- ✅ Every correction is **auditable and reversible** — it's a line of code or a config
  entry, not a destroyed cell; the raw bag/inches are always recoverable.
- ✅ Re-exporting a day from the app is safe: dedup absorbs the overlap.
- ✅ The net-tare adjustment can be turned off (empty the map) without touching data.
- ⚠️ Reconciliation tests must **guard** these corrections so a loader change can't
  silently drift the totals away from the measured bags.
- ⚠️ The loader reads columns **by name**, so a correction depends on the expected
  column being present (the xlsx schema is known to evolve).

## Alternatives considered

- **Edit the spreadsheet / CSVs in place** (subtract the net, delete dup rows, fill
  inches): rejected — irreversible, destroys the audit trail, and fights the "files are
  sacred" invariant from ADR 0002.
- **A cleaned copy as a new source of truth:** rejected — that's a second sacred file to
  keep in sync; derivation at load time keeps exactly one origin.
