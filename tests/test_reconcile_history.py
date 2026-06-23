"""DATA-1 (HAY-120) reconciliation — migrated historical CSVs must reproduce the xlsx.

Asserts (per docs/data1-migration-design.md §5):
  A. per-year walleye catch counts == {2023:32, 2024:30, 2025:11}
  B. Σ daily_wt_lbs per trip == trip totals 41.3 / 48.0 / 19.49
  C. measured trip wt/inch ≈ 0.083 / 0.095 / 0.111
  E. end-to-end: load_history() -> estimate_weights reproduces per-year bag totals.

Also REPRODUCES-AND-WARNS (does NOT auto-fix) the known 2024-06-15 inch discrepancy
(logged walleye inches 240.75 vs recorded day_inches 250.75).

Run:  uv run python tests/test_reconcile_history.py     (prints PASS / warnings)
  or: uv run pytest tests/test_reconcile_history.py -q -s
"""
from __future__ import annotations

import os
import sys
import warnings

import pandas as pd

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import analysis as A  # noqa: E402

HIST = os.path.join(ROOT, 'historical')
EPS = 1e-6

EXPECT_COUNTS = {2023: 32, 2024: 30, 2025: 11}
EXPECT_TRIP_WT = {'2023-06': 41.3, '2024-06': 48.0, '2025-06': 19.49}
EXPECT_TRIP_WPI = {'2023-06': 0.083, '2024-06': 0.095, '2025-06': 0.111}


def _load_hist_only():
    """load_history restricted to the migrated historical/ tree (no 2026 exports)."""
    return A.load_history(roots=(HIST,))


def test_per_year_walleye_counts():
    fish, _ = _load_hist_only()
    got = fish.groupby('year').size().to_dict()
    for yr, n in EXPECT_COUNTS.items():
        assert got.get(yr) == n, f"{yr}: expected {n} walleye, got {got.get(yr)}"


def test_daily_bags_sum_to_trip_totals():
    _, daily = _load_hist_only()
    by_trip = daily.groupby('trip')['daily_wt_lbs'].sum().to_dict()
    for trip, total in EXPECT_TRIP_WT.items():
        assert abs(by_trip[trip] - total) < EPS, \
            f"{trip}: Σdaily_wt_lbs {by_trip[trip]} != trip total {total}"


def test_measured_trip_wt_per_inch():
    """Measured (bag ÷ day_inches) trip wt/inch ≈ expected (~0.083/0.095/0.111)."""
    _, daily = _load_hist_only()
    g = daily.groupby('trip').agg(wt=('daily_wt_lbs', 'sum'),
                                  inch=('day_inches', 'sum'))
    g['wpi'] = g['wt'] / g['inch']
    for trip, wpi in EXPECT_TRIP_WPI.items():
        assert abs(g.loc[trip, 'wpi'] - wpi) < 5e-3, \
            f"{trip}: trip wt/inch {g.loc[trip,'wpi']:.5f} != ~{wpi}"


def test_end_to_end_bag_totals_reproduced():
    """estimate_weights over the migrated store reproduces per-year measured bags."""
    fish, daily = _load_hist_only()
    fit = A.fit_length_weight(fish)
    b = fit['b'] if fit else A.B_LITERATURE
    fish = A.estimate_weights(fish, daily, b)
    by_year = fish.groupby('year')['weight_est'].sum().to_dict()
    expect = {2023: 41.3, 2024: 48.0, 2025: 19.49}
    for yr, total in expect.items():
        assert abs(by_year[yr] - total) < 1e-4, \
            f"{yr}: modeled total {by_year[yr]} != measured bag {total}"


def test_known_2024_06_15_inch_discrepancy_warns():
    """REPRODUCE-AND-WARN: logged walleye inches 240.75 vs recorded day_inches 250.75.

    Must NOT auto-fix: day_inches is migrated as-recorded (250.75). The test asserts
    the discrepancy is faithfully preserved and emits a warning rather than failing.
    """
    fish, daily = _load_hist_only()
    ws = 'hist-2024-06-15'
    logged = fish.loc[fish['weigh_session_id'] == ws, 'length'].sum()
    recorded = float(daily.loc[daily['weigh_session_id'] == ws, 'day_inches'].iloc[0])

    # day_inches preserved as-recorded (never silently corrected to the logged sum).
    assert abs(recorded - 250.75) < EPS, "day_inches must stay as-recorded (250.75)"
    assert abs(logged - 240.75) < EPS, f"logged walleye inches {logged} != 240.75"
    gap = recorded - logged
    if abs(gap) > EPS:
        warnings.warn(
            f"KNOWN 2024-06-15 inch discrepancy: logged walleye inches "
            f"{logged:.2f} vs recorded day_inches {recorded:.2f} (gap {gap:+.2f}). "
            f"Preserved as-recorded; NOT auto-fixed (does not affect bag-calibrated "
            f"weight estimates).",
            stacklevel=2,
        )


if __name__ == '__main__':
    checks = [
        ('A per-year walleye counts 32/30/11', test_per_year_walleye_counts),
        ('B daily bags sum to 41.3/48.0/19.49', test_daily_bags_sum_to_trip_totals),
        ('C measured trip wt/inch ~0.083/0.095/0.111', test_measured_trip_wt_per_inch),
        ('E end-to-end bag totals reproduced', test_end_to_end_bag_totals_reproduced),
    ]
    for name, fn in checks:
        fn()
        print(f"PASS  {name}")
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter('always')
        test_known_2024_06_15_inch_discrepancy_warns()
        for wi in w:
            print(f"WARN  {wi.message}")
    print("\nAll reconciliation checks passed.")
