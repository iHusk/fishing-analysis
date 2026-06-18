# ADR 0001 — Walleye weight estimation curve

- **Status:** Accepted
- **Date:** 2026-06-18
- **Deciders:** Tyler (project owner)

## Context

Each fish record has a **length** but not (yet) an individual weight. We need a
per-fish weight estimate to analyze size/quality and to compute trip and per-year
totals. Constraints and facts:

- Fish weight scales with length roughly **cubed**, not linearly. The legacy model
  (`weight_calc` = `length × 0.0921 lb/in`, a constant) over-weights small fish and
  badly under-weights large ones (it capped a 21″ fish near 2 lb).
- The **bag is weighed every day at cleaning** (`daily_wt_lbs` per `weigh_date`), and
  per-trip totals are also recorded. These daily totals are trusted **ground truth**.
- Published walleye length–weight exponents are well established ("known knowns"):
  **b = 3.180** (standard-weight equation; Murphy et al. 1990; Anderson & Neumann 1996)
  and **b ≈ 3.061** for Lake Oahe, SD specifically (Carlander's Handbook).
- A bag total only constrains the **sum** of weights, so the exponent `b` is **not
  identifiable** from bag weights alone — fitting `b` to our 6 measured daily bags
  yields 1.7–5.9 depending on which days are included.

## Decision

Estimate weight with the power law **W = a · Lᵇ**, where:

1. **Exponent `b`** defaults to the literature value **3.180** (`B_LITERATURE`; the
   Oahe-specific 3.061 is a one-line alternative). It is **not** fitted from bag totals.
2. **Coefficient `a`** is **calibrated per weigh-day** so each day's estimates sum
   exactly to the measured `daily_wt_lbs`:
   `a_day = daily_wt_lbs / Σ(Lᵇ over that day's fish)`. Days without a measured bag use
   a pooled `a`. This preserves the trusted daily/trip totals exactly while distributing
   weight realistically across fish.
3. **Fit path (forward-looking):** an optional per-fish **`measured_wt_lbs`** column
   (to be populated by the data-entry app for a sample of fish) enables a direct
   **log-log OLS fit** of `W = a·Lᵇ`. Once at least `MIN_FIT_N` (=12) individual
   weights exist, the fitted exponent **supersedes** the literature default as the curve
   shape; per-day bag calibration of `a` is still applied so totals stay exact.

Relative weight (condition) is reported as `Wr = 100·W/Ws` using the English-unit walleye
standard weight `log10 Ws = -3.643 + 3.180·log10 L` (Wr ≈ 100 = standard).

## Consequences

- ✅ Daily and per-year totals always match the measured bags exactly.
- ✅ Per-fish weights are biologically realistic (≈0.7–4.1 lb vs. the linear 1.2–2.1 lb).
- ✅ The model **auto-improves**: it switches to a data-fitted exponent the moment enough
  individual weights are logged — no code change required.
- ⚠️ Depends on each fish carrying a `weigh_date` and on the daily anchor table. The
  loader reads columns **by name** (resilient to the frequently-changing column order);
  the per-fish individual-weight column must be named `measured_wt_lbs`.
- ⚠️ Until individual weights exist, the curve **shape** rests on the literature exponent,
  not our own fish. That is an explicit, documented assumption.

## Alternatives considered

- **Linear lb/inch (legacy):** rejected — wrong shape; mis-estimates at size extremes.
- **Fit `b` from the measured bag totals:** rejected — `b` is unidentifiable from sums;
  the fit is unstable (1.7–5.9). See `docs/methodology.md`.
- **Single global `a` across all years:** rejected — ignores real year-to-year condition
  differences (mean Wr 88/90/107 for 2023/24/25) and fits the bags worse.
