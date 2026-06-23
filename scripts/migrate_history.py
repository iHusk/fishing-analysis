"""DATA-1 (HAY-120) — migrate the frozen historical xlsx into the LOCKED CSV schema.

Reads ``fishing-trip.xlsx`` **READ-ONLY** and writes NEW files only:
    historical/<year>/catches.csv
    historical/<year>/daily_weights.csv

Schema reference: docs/data1-migration-design.md + docs/app-build-plan.md
(LOCKED) + exports/2026/20260620/*.csv.

Synthesized join/identity keys ONLY:
  * ``uuid``            = deterministic uuid5(NS, "hist-<year>-<id>")
  * ``weigh_session_id``= "hist-<weigh_date:YYYY-MM-DD>"

Everything not captured historically is left BLANK (never fabricated):
  ``timestamp_utc, lat, lon, gps_accuracy_m, heading_deg, water_temp_f``.

The xlsx is NEVER written. Run:  uv run python scripts/migrate_history.py
"""
from __future__ import annotations

import uuid
from pathlib import Path

import pandas as pd

# Repo root = parent of this scripts/ dir, so the script is CWD-independent.
ROOT = Path(__file__).resolve().parent.parent
XLSX = ROOT / "fishing-trip.xlsx"
OUT_ROOT = ROOT / "historical"

# Fixed namespace so re-runs produce byte-identical UUIDs (dedup-safe).
HIST_NS = uuid.UUID("00000000-0000-0000-0000-000000000000")

# LOCKED target headers (docs/app-build-plan.md "Final data schema").
CATCHES_COLS = [
    "id", "uuid", "timestamp_local", "timestamp_utc", "year", "weigh_session_id",
    "trip", "fisherman", "species", "kept", "length_in", "depth_ft", "water_temp_f",
    "lure_color1", "lure_color2", "bait", "location_name", "lat", "lon",
    "gps_accuracy_m", "heading_deg", "notes",
]
DAILY_COLS = [
    "weigh_session_id", "weigh_date", "trip", "daily_wt_lbs", "day_inches",
    "daily_wt_per_inch", "n_catches_logged", "notes",
]

PERFISH_SRC = [
    "id", "year", "fisherman", "day", "datetime", "fish_species", "kept",
    "length", "depth", "bait", "weight_calc", "location", "lure_color_1",
    "lure_color_2", "trip", "weigh_date",
]


def _norm_trip(val) -> str:
    """Normalize legacy trip (`2023-06-01` / Timestamp) to the app's `YYYY-MM`."""
    ts = pd.to_datetime(val)
    return f"{ts.year:04d}-{ts.month:02d}"


def _ws_id(weigh_date) -> str:
    return "hist-" + pd.to_datetime(weigh_date).strftime("%Y-%m-%d")


def read_source(path: Path = XLSX):
    """READ-ONLY load of the legacy Sheet1 into (per-fish, daily-anchor) frames."""
    full = pd.read_excel(path)

    fish = full[PERFISH_SRC].copy()
    fish["datetime"] = pd.to_datetime(fish["datetime"])
    fish["weigh_date"] = pd.to_datetime(fish["weigh_date"])

    # Daily anchor table lives in the duplicate-suffixed columns (R:V block).
    daily = full[["weigh_date.1", "trip.1", "daily_wt_lbs", "day_inches",
                  "daily_wt_per_inch"]].copy()
    daily.columns = ["weigh_date", "trip", "daily_wt_lbs", "day_inches",
                     "daily_wt_per_inch"]
    # The R:V block is co-located with the trip-totals block (its numbers bleed into
    # the same columns). The 6 GENUINE weigh-day rows are the only ones carrying a
    # populated `daily_wt_per_inch`; the trip-totals rows leave it blank. Gate on it
    # to isolate the daily anchor (daily_wt_lbs is then fully populated, per design).
    daily = daily[daily["daily_wt_per_inch"].notna()].copy()
    daily["weigh_date"] = pd.to_datetime(daily["weigh_date"])
    for c in ("daily_wt_lbs", "day_inches", "daily_wt_per_inch"):
        daily[c] = pd.to_numeric(daily[c], errors="coerce")
    assert daily["daily_wt_lbs"].notna().all(), "daily_wt_lbs must be fully populated"
    return fish, daily


def build_catches(fish: pd.DataFrame) -> pd.DataFrame:
    """Map ALL per-fish rows (incl. the 1 perch) to the locked catches schema."""
    out = pd.DataFrame(index=fish.index, columns=CATCHES_COLS)

    out["id"] = fish["id"].astype("Int64")
    out["uuid"] = [
        str(uuid.uuid5(HIST_NS, f"hist-{int(y)}-{int(i)}"))
        for y, i in zip(fish["year"], fish["id"])
    ]
    out["timestamp_local"] = fish["datetime"].dt.strftime("%Y-%m-%d %H:%M:%S")
    out["timestamp_utc"] = ""                              # blank: no tz historically
    out["year"] = fish["year"].astype("Int64")
    out["weigh_session_id"] = fish["weigh_date"].map(_ws_id)
    out["trip"] = fish["trip"].map(_norm_trip)
    out["fisherman"] = fish["fisherman"]
    out["species"] = fish["fish_species"].str.lower()
    out["kept"] = fish["kept"].map(lambda b: "true" if bool(b) else "false")
    out["length_in"] = fish["length"]
    out["depth_ft"] = fish["depth"]                        # stored positive; loader flips
    out["water_temp_f"] = ""                               # blank: not captured pre-app
    out["lure_color1"] = fish["lure_color_1"]
    out["lure_color2"] = fish["lure_color_2"]
    out["bait"] = fish["bait"]
    out["location_name"] = fish["location"]
    out["lat"] = ""
    out["lon"] = ""
    out["gps_accuracy_m"] = ""
    out["heading_deg"] = ""
    out["notes"] = "migrated:xlsx-Sheet1"
    return out


def build_daily(daily: pd.DataFrame, catches: pd.DataFrame) -> pd.DataFrame:
    """Map the 6 weigh-day anchor rows to the locked daily_weights schema."""
    out = pd.DataFrame(index=daily.index, columns=DAILY_COLS)
    ws = daily["weigh_date"].map(_ws_id)

    # n_catches_logged: count migrated catches feeding the calibration denominator
    # for that session = KEPT WALLEYE (the pipeline filters species to walleye and
    # excludes kept==false). This reproduces the design's §5C table 16/16/15/15/5/6
    # and is why it stays 15 for 2024-06-15 even though a perch shares the session.
    anchor = catches[(catches["kept"] == "true") & (catches["species"] == "walleye")]
    n_by_ws = anchor.groupby("weigh_session_id")["id"].count()

    out["weigh_session_id"] = ws.values
    out["weigh_date"] = daily["weigh_date"].dt.strftime("%Y-%m-%d").values
    out["trip"] = daily["trip"].map(_norm_trip).values
    out["daily_wt_lbs"] = daily["daily_wt_lbs"].values
    out["day_inches"] = daily["day_inches"].values         # as-recorded; never "fixed"
    out["daily_wt_per_inch"] = daily["daily_wt_per_inch"].values
    out["n_catches_logged"] = [int(n_by_ws.get(w, 0)) for w in ws]
    out["notes"] = ""
    return out


def write_by_year(catches: pd.DataFrame, daily: pd.DataFrame,
                  out_root: Path = OUT_ROOT) -> list[Path]:
    """Write NEW files only, partitioned historical/<year>/{catches,daily_weights}.csv."""
    written: list[Path] = []
    years = sorted(catches["year"].dropna().astype(int).unique())
    for year in years:
        ydir = out_root / str(year)
        ydir.mkdir(parents=True, exist_ok=True)

        c = catches[catches["year"] == year].copy()
        # daily rows belong to the year embedded in the weigh_session_id date.
        d = daily[daily["weigh_session_id"].str[5:9].astype(int) == year].copy()

        cpath = ydir / "catches.csv"
        dpath = ydir / "daily_weights.csv"
        c.to_csv(cpath, index=False)
        d.to_csv(dpath, index=False)
        written += [cpath, dpath]
    return written


def main() -> list[Path]:
    fish, daily = read_source()
    catches = build_catches(fish)
    daily_out = build_daily(daily, catches)
    written = write_by_year(catches, daily_out)
    for p in written:
        print(f"wrote {p.relative_to(ROOT)}")
    return written


if __name__ == "__main__":
    main()
