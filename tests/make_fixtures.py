#!/usr/bin/env python3
"""Generate synthetic FishingLogger exports for testing replay_trip.py.

Builds a realistic multi-day weekend trip + a pile of edge cases under a target dir.
Run:  uv run python tests/make_fixtures.py /tmp/fixtures
"""
import csv
import math
import sys
from pathlib import Path

CATCH_COLS = ["id","uuid","timestamp_local","timestamp_utc","year","weigh_session_id",
    "trip","fisherman","species","kept","length_in","depth_ft","water_temp_f",
    "lure_color1","lure_color2","bait","location_name","lat","lon","gps_accuracy_m",
    "heading_deg","notes"]
TRACK_COLS = ["timestamp_utc","timestamp_local","trip","weigh_session_id","lat","lon",
    "accuracy_m","altitude_m","speed_mps","course_deg"]
WEIGHT_COLS = ["weigh_session_id","weigh_date","trip","daily_wt_lbs","day_inches",
    "daily_wt_per_inch","n_catches_logged","notes"]


def write_csv(path, cols, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})


def ts(day, sec):
    """day=0..,sec from 06:00. Returns (local,utc,year,date)."""
    base_h = 6
    total = base_h * 3600 + sec
    hh = (total // 3600) % 24
    mm = (total // 60) % 60
    ss = total % 60
    date = f"2026-06-{18+day:02d}"
    local = f"{date} {hh:02d}:{mm:02d}:{ss:02d}"
    uh = (hh + 5) % 24
    utc = f"{date} {uh:02d}:{mm:02d}:{ss:02d}"
    return local, utc, "2026", date


def gen_day(day, n_track=600, n_catch=4, trip="2026-06",
            lat0=44.50, lon0=-100.43, anglers=("Tyler","Cody")):
    """A wandering troll with occasional runs; catches sprinkled along the way."""
    wsid = f"2026-06-{18+day:02d}"
    track, catches = [], []
    lat, lon, course = lat0, lon0, 90.0
    for i in range(n_track):
        # mostly trolling (~1 m/s), bursts of running (~12 m/s) every ~150 pts
        running = (i % 170) < 25
        speed = 11.5 if running else (0.6 + 0.8 * abs(math.sin(i / 9)))
        course = (course + (8 if running else 2) * math.sin(i / 13)) % 360
        d = speed / 111320.0  # ~deg per sec
        lat += d * math.cos(math.radians(course))
        lon += d * math.sin(math.radians(course)) / math.cos(math.radians(lat))
        local, utc, year, date = ts(day, i)
        track.append({
            "timestamp_utc": utc, "timestamp_local": local, "trip": trip,
            "weigh_session_id": wsid, "lat": f"{lat:.6f}", "lon": f"{lon:.6f}",
            "accuracy_m": f"{3.0 + (i % 5) * 0.4:.2f}", "altitude_m": "510.2",
            "speed_mps": f"{speed:.2f}", "course_deg": f"{course:.1f}",
        })
    species = ["walleye","walleye","sauger","walleye","northern pike","perch","white bass"]
    for j in range(n_catch):
        idx = int((j + 0.5) / n_catch * n_track)
        tp = track[idx]
        local, utc, year, date = ts(day, idx)
        kept = "false" if (day + j) % 5 == 0 else "true"
        catches.append({
            "id": f"{day}{j}", "uuid": f"uuid-{day}-{j}",
            "timestamp_local": local, "timestamp_utc": utc, "year": "2026",
            "weigh_session_id": wsid, "trip": trip,
            "fisherman": anglers[j % len(anglers)],
            "species": species[(day + j) % len(species)],
            "kept": kept,
            "length_in": str(14 + (j * 5 + day * 3) % 24),
            "depth_ft": str(18 + (j * 7) % 25),
            "water_temp_f": str(64 + day) if j == 0 else "",
            "lure_color1": ["Firetiger","White","Chartreuse","Gold","Bare"][j % 5],
            "lure_color2": ["Red Hooks",""][j % 2],
            "bait": ["nightcrawler",""][j % 2],
            "location_name": "",
            "lat": tp["lat"], "lon": tp["lon"],
            "gps_accuracy_m": tp["accuracy_m"], "heading_deg": tp["course_deg"],
            "notes": "tank!" if int(track[idx]["speed_mps"].split('.')[0]) < 2 and j == 1 else "",
        })
    weight = {
        "weigh_session_id": wsid, "weigh_date": wsid, "trip": trip,
        "daily_wt_lbs": str(8 + day * 2), "day_inches": "", "daily_wt_per_inch": "",
        "n_catches_logged": str(n_catch), "notes": "",
    }
    return track, catches, weight


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "/tmp/fixtures")

    # --- 3-day weekend, ONE folder (multi-day via weigh_session_id) ---
    t_all, c_all, w_all = [], [], []
    for day in range(3):
        t, c, w = gen_day(day, lat0=44.50 + day * 0.02, lon0=-100.43 - day * 0.01)
        t_all += t; c_all += c; w_all.append(w)
    write_csv(root / "weekend" / "catches.csv", CATCH_COLS, c_all)
    write_csv(root / "weekend" / "track.csv", TRACK_COLS, t_all)
    write_csv(root / "weekend" / "daily_weights.csv", WEIGHT_COLS, w_all)

    # --- same weekend as SEPARATE per-day folders (for --all stitching) ---
    for day in range(3):
        t, c, w = gen_day(day, lat0=44.50 + day * 0.02, lon0=-100.43 - day * 0.01)
        sub = root / "season" / f"day{day+1}"
        write_csv(sub / "catches.csv", CATCH_COLS, c)
        write_csv(sub / "track.csv", TRACK_COLS, t)
        write_csv(sub / "daily_weights.csv", WEIGHT_COLS, [w])

    # --- edge: no daily_weights ---
    t, c, _ = gen_day(0)
    write_csv(root / "no_weights" / "catches.csv", CATCH_COLS, c)
    write_csv(root / "no_weights" / "track.csv", TRACK_COLS, t)

    # --- edge: catches with NO GPS + one bad-accuracy fix ---
    t, c, w = gen_day(0, n_catch=4)
    c[0]["lat"] = ""; c[0]["lon"] = ""            # no GPS -> excluded from map
    c[1]["gps_accuracy_m"] = "150"                 # too inaccurate -> excluded
    t[5]["accuracy_m"] = "200"                     # bad track fix -> dropped
    write_csv(root / "messy_gps" / "catches.csv", CATCH_COLS, c)
    write_csv(root / "messy_gps" / "track.csv", TRACK_COLS, t)

    # --- edge: catches but NO track at all ---
    _, c, _ = gen_day(0)
    write_csv(root / "catches_only" / "catches.csv", CATCH_COLS, c)

    # --- edge: track but NO catches (a skunk day) ---
    t, _, _ = gen_day(0)
    write_csv(root / "skunked" / "track.csv", TRACK_COLS, t)

    # --- edge: tiny (1 track pt, 1 catch) ---
    t, c, _ = gen_day(0, n_track=2, n_catch=1)
    write_csv(root / "tiny" / "track.csv", TRACK_COLS, t[:1])
    write_csv(root / "tiny" / "catches.csv", CATCH_COLS, c[:1])

    # --- edge: blank speed/course everywhere ---
    t, c, _ = gen_day(0)
    for r in t:
        r["speed_mps"] = ""; r["course_deg"] = ""
    write_csv(root / "no_speed" / "catches.csv", CATCH_COLS, c)
    write_csv(root / "no_speed" / "track.csv", TRACK_COLS, t)

    # --- edge: empty files (headers only) ---
    write_csv(root / "empty" / "catches.csv", CATCH_COLS, [])
    write_csv(root / "empty" / "track.csv", TRACK_COLS, [])

    print(f"fixtures written under {root}")
    for p in sorted(root.rglob("*.csv")):
        print("  ", p.relative_to(root))


if __name__ == "__main__":
    main()
