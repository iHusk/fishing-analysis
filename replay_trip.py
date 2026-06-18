#!/usr/bin/env python3
"""
replay_trip.py — turn a FishingLogger export into a sexy, self-contained replay map.

Reads the app's exported CSVs (catches.csv, track.csv, optional daily_weights.csv) and
renders ONE standalone .html file: a satellite map where the boat's GPS track unfolds
along a time slider, the catch pins pop in at the exact spot + moment each fish was
landed, and a whole weekend's worth of days can be stitched together and replayed.

Usage
-----
    # one export folder -> replay_<trip>.html in that folder
    uv run --with pandas python replay_trip.py path/to/export_dir

    # stitch every export subfolder under a parent into one multi-day replay
    uv run --with pandas python replay_trip.py --all path/to/parent_dir

    # choose the output file
    uv run --with pandas python replay_trip.py export_dir -o ~/Desktop/oahe.html

No internet is needed to *generate* the file; the map tiles (satellite) load from the
web when you open the HTML, so view it on camp/home wifi.

Design notes live in docs/replay-map-spec.md. Schema is the LOCKED app export schema.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

try:
    import pandas as pd
except ModuleNotFoundError:  # pragma: no cover - friendly hint
    sys.exit(
        "pandas is required. Run me with uv, e.g.:\n"
        "    uv run --with pandas python replay_trip.py <export_dir>"
    )

# --------------------------------------------------------------------------------------
# Tunables
# --------------------------------------------------------------------------------------

ACCURACY_LIMIT_M = 30.0        # drop GPS fixes worse than this (track + catches)
GAP_SKIP_SECONDS = 180         # in playback, fast-forward idle/overnight gaps longer than this
MAX_REVEAL_POINTS = 4000       # decimate the *animated* track to keep playback buttery
TROLL_SPEED_MPS = 1.6          # <= this reads as "fishing / trolling" (gold)
RUN_SPEED_MPS = 4.5            # >= this reads as "running" (blue)
LENGTH_MIN_IN = 1.0            # ignore implausible fish lengths outside [MIN, MAX]
LENGTH_MAX_IN = 80.0

# Per-day track colors (cycled). Picked to glow on a dark satellite basemap.
DAY_COLORS = [
    "#ffd24d", "#4dd2ff", "#ff7b54", "#9b8cff", "#5cffb1",
    "#ff6ad5", "#ffe66d", "#54c7ff", "#c0ff54", "#ff9f54",
]

# Fisherman marker colors (cycled, assigned in first-seen order).
FISHERMAN_COLORS = [
    "#ff4d6d", "#4dabf7", "#51cf66", "#ffd43b", "#cc5de8",
    "#ff922b", "#22d3ee", "#f783ac", "#94d82d", "#9775fa",
]

# Species -> emoji used on pins / in legend. Falls back to a generic fish.
SPECIES_EMOJI = {
    "walleye": "🐟",
    "sauger": "🐠",
    "perch": "🐡",
    "northern pike": "🐊",
    "pike": "🐊",
    "smallmouth bass": "🎣",
    "largemouth bass": "🎣",
    "white bass": "🐟",
    "crappie": "🪸",
    "catfish": "🐱",
    "chinook salmon": "🍣",
    "salmon": "🍣",
    "trout": "🐟",
}
# substring aliases tried (in order) when the exact name misses — keeps free-text typos themed
SPECIES_ALIASES = [
    ("walleye", "🐟"), ("sauger", "🐠"), ("perch", "🐡"),
    ("pike", "🐊"), ("muskie", "🐊"), ("musky", "🐊"), ("muskellunge", "🐊"),
    ("smallmouth", "🎣"), ("largemouth", "🎣"), ("bass", "🎣"),
    ("crappie", "🪸"), ("cat", "🐱"), ("salmon", "🍣"), ("trout", "🐟"),
]
DEFAULT_EMOJI = "🐟"


def emoji_for(species: str) -> str:
    s = (species or "").strip().lower()
    if s in SPECIES_EMOJI:
        return SPECIES_EMOJI[s]
    for token, emo in SPECIES_ALIASES:
        if token in s:
            return emo
    return DEFAULT_EMOJI


# --------------------------------------------------------------------------------------
# Loading + cleaning
# --------------------------------------------------------------------------------------

@dataclass
class Loaded:
    catches: pd.DataFrame
    track: pd.DataFrame
    weights: pd.DataFrame
    dropped_track_bad: int = 0      # missing/invalid lat/lon/time or out-of-range coords
    dropped_track_acc: int = 0      # dropped purely for poor GPS accuracy
    dropped_catch_acc: int = 0
    dropped_catch_nogps: int = 0
    dropped_catch_coord: int = 0    # out-of-range / null-island coords
    dropped_catch_notime: int = 0   # valid GPS but no usable timestamp (can't be animated)
    source: str = ""


def _read_csv(path: Path) -> pd.DataFrame:
    if not path.exists():
        return pd.DataFrame()
    try:
        # utf-8-sig strips a BOM if present; keep blanks as "" not NaN
        df = pd.read_csv(path, dtype=str, keep_default_na=False, encoding="utf-8-sig")
    except Exception as exc:  # pragma: no cover - corrupt file
        print(f"  ! could not read {path.name}: {exc}", file=sys.stderr)
        return pd.DataFrame()
    df.columns = df.columns.str.strip()   # tolerate hand-edited headers with stray spaces
    return df


def _to_float(series: pd.Series) -> pd.Series:
    return pd.to_numeric(series, errors="coerce")


def _parse_local(ts: pd.Series) -> pd.Series:
    """Parse 'YYYY-MM-DD HH:MM:SS' local wall-clock -> naive datetime."""
    return pd.to_datetime(ts, errors="coerce")


def _bad_coords(lat: pd.Series, lon: pd.Series) -> pd.Series:
    """True where coordinates are out of range or the (0,0) 'null island' no-fix sentinel."""
    out_of_range = ~(lat.between(-90, 90) & lon.between(-180, 180))
    null_island = (lat == 0) & (lon == 0)
    return out_of_range | null_island


def load_export(export_dir: Path) -> Loaded:
    """Load + clean one export folder. Robust to blanks and missing optional files."""
    catches = _read_csv(export_dir / "catches.csv")
    track = _read_csv(export_dir / "track.csv")
    weights = _read_csv(export_dir / "daily_weights.csv")

    out = Loaded(catches=catches, track=track, weights=weights, source=export_dir.name)

    # --- track ---
    if not track.empty:
        track = track.copy()
        for col in ("lat", "lon", "accuracy_m", "altitude_m", "speed_mps", "course_deg"):
            if col in track:
                track[col] = _to_float(track[col])
        track["t"] = _parse_local(track.get("timestamp_local"))
        n0 = len(track)
        track = track.dropna(subset=["lat", "lon", "t"])
        bad = _bad_coords(track["lat"], track["lon"])
        track = track[~bad]
        out.dropped_track_bad = n0 - len(track)
        acc = track.get("accuracy_m")
        if acc is not None:
            n1 = len(track)
            track = track[acc.isna() | (acc <= ACCURACY_LIMIT_M)]
            out.dropped_track_acc = n1 - len(track)
        track = track.sort_values("t").reset_index(drop=True)
    out.track = track

    # --- catches ---
    if not catches.empty:
        catches = catches.copy()
        for col in ("lat", "lon", "gps_accuracy_m", "length_in", "depth_ft",
                    "water_temp_f", "heading_deg"):
            if col in catches:
                catches[col] = _to_float(catches[col])
        catches["t"] = _parse_local(catches.get("timestamp_local"))
        # keep catches with no GPS out of the *map* but count them
        has_gps = catches["lat"].notna() & catches["lon"].notna()
        out.dropped_catch_nogps = int((~has_gps).sum())
        catches = catches[has_gps]
        bad = _bad_coords(catches["lat"], catches["lon"])
        out.dropped_catch_coord = int(bad.sum())
        catches = catches[~bad]
        acc = catches.get("gps_accuracy_m")
        if acc is not None:
            n1 = len(catches)
            catches = catches[acc.isna() | (acc <= ACCURACY_LIMIT_M)]
            out.dropped_catch_acc = n1 - len(catches)
        # a catch with no usable timestamp can never be placed on the timeline -> drop+count
        notime = catches["t"].isna()
        out.dropped_catch_notime = int(notime.sum())
        catches = catches[~notime]
        catches = catches.sort_values("t").reset_index(drop=True)
    out.catches = catches

    return out


def merge_loaded(items: list[Loaded]) -> Loaded:
    """Concatenate several loaded exports (for --all multi-trip stitching)."""
    def cat(attr):
        frames = [getattr(i, attr) for i in items if not getattr(i, attr).empty]
        return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()

    merged = Loaded(
        catches=cat("catches"), track=cat("track"), weights=cat("weights"),
        dropped_track_bad=sum(i.dropped_track_bad for i in items),
        dropped_track_acc=sum(i.dropped_track_acc for i in items),
        dropped_catch_acc=sum(i.dropped_catch_acc for i in items),
        dropped_catch_nogps=sum(i.dropped_catch_nogps for i in items),
        dropped_catch_coord=sum(i.dropped_catch_coord for i in items),
        dropped_catch_notime=sum(i.dropped_catch_notime for i in items),
        source=", ".join(i.source for i in items),
    )
    if not merged.track.empty:
        merged.track = merged.track.sort_values("t").reset_index(drop=True)
    if not merged.catches.empty:
        merged.catches = merged.catches.sort_values("t").reset_index(drop=True)
    return merged


# --------------------------------------------------------------------------------------
# Geometry / stats helpers
# --------------------------------------------------------------------------------------

def haversine_m(lat1, lon1, lat2, lon2) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def decimate(points: list[dict], cap: int) -> list[dict]:
    """Evenly thin a list to <= cap, always keeping first + last."""
    n = len(points)
    if n <= cap:
        return points
    step = n / cap
    idx = sorted(set([0, n - 1] + [int(i * step) for i in range(cap - 1)]))
    return [points[i] for i in idx if i < n]


# --------------------------------------------------------------------------------------
# Build the JSON payload the front-end animates
# --------------------------------------------------------------------------------------

def _epoch_s(t) -> float | None:
    """Seconds for a naive local wall-clock. Treated as UTC so the *clock* is rendered
    verbatim by the front-end (which uses UTC getters) regardless of the viewer's tz."""
    if pd.isna(t):
        return None
    return float(pd.Timestamp(t).tz_localize("UTC").timestamp())


def build_payload(data: Loaded, title: str) -> dict:
    track, catches, weights = data.track, data.catches, data.weights

    # group key: prefer weigh_session_id, else the calendar date of the timestamp
    def group_of(df: pd.DataFrame) -> pd.Series:
        wsid = df.get("weigh_session_id")
        if wsid is not None:
            wsid = wsid.fillna("").astype(str).str.strip()
        else:
            wsid = pd.Series([""] * len(df), index=df.index)
        date = df["t"].dt.strftime("%Y-%m-%d").fillna("unknown")
        return wsid.where(wsid != "", date)

    track_g = group_of(track) if not track.empty else pd.Series(dtype=str)
    catch_g = group_of(catches) if not catches.empty else pd.Series(dtype=str)

    day_ids = sorted(set(list(track_g.unique()) + list(catch_g.unique())))

    # fisherman color map (first-seen order across all catches)
    fishermen = []
    if not catches.empty:
        for f in catches.get("fisherman", pd.Series(dtype=str)).fillna(""):
            f = (f or "").strip() or "Unknown"
            if f not in fishermen:
                fishermen.append(f)
    fisher_color = {f: FISHERMAN_COLORS[i % len(FISHERMAN_COLORS)]
                    for i, f in enumerate(fishermen)}

    days = []
    all_lat, all_lon = [], []
    total_distance = 0.0
    total_track_seconds = 0.0

    for di, gid in enumerate(day_ids):
        color = DAY_COLORS[di % len(DAY_COLORS)]

        # --- track points for this day ---
        tpts = []
        if not track.empty:
            sub = track[track_g.values == gid]
            prev = None
            seg_seconds = 0.0
            for _, r in sub.iterrows():
                ts = _epoch_s(r["t"])
                if ts is None:
                    continue
                lat, lon = float(r["lat"]), float(r["lon"])
                spd = r.get("speed_mps")
                spd = float(spd) if pd.notna(spd) else None
                crs = r.get("course_deg")
                crs = float(crs) if pd.notna(crs) else None
                tpts.append({"lat": lat, "lon": lon, "t": ts, "s": spd, "c": crs})
                all_lat.append(lat); all_lon.append(lon)
                if prev is not None:
                    total_distance += haversine_m(prev[0], prev[1], lat, lon)
                    dt = ts - prev[2]
                    if 0 < dt <= GAP_SKIP_SECONDS:
                        seg_seconds += dt
                prev = (lat, lon, ts)
            total_track_seconds += seg_seconds

        # decimate the animated track but keep timing fidelity
        tpts = decimate(tpts, MAX_REVEAL_POINTS)

        # --- catches for this day ---
        cpts = []
        if not catches.empty:
            sub = catches[catch_g.values == gid]
            for _, r in sub.iterrows():
                ts = _epoch_s(r["t"])
                lat, lon = float(r["lat"]), float(r["lon"])
                all_lat.append(lat); all_lon.append(lon)
                fisher = (r.get("fisherman") or "").strip() or "Unknown"
                species = (r.get("species") or "").strip() or "fish"
                kept_raw = (str(r.get("kept")) or "").strip().lower()
                kept = kept_raw in ("true", "1", "yes", "t", "y")
                cpts.append({
                    "lat": lat, "lon": lon, "t": ts,
                    "uuid": (r.get("uuid") or "").strip(),
                    "fisher": fisher,
                    "color": fisher_color.get(fisher, "#ffffff"),
                    "species": species,
                    "emoji": emoji_for(species),
                    "len": _len(r.get("length_in")),
                    "depth": _num(r.get("depth_ft")),
                    "temp": _num(r.get("water_temp_f")),
                    "lure1": (r.get("lure_color1") or "").strip(),
                    "lure2": (r.get("lure_color2") or "").strip(),
                    "bait": (r.get("bait") or "").strip(),
                    "loc": (r.get("location_name") or "").strip(),
                    "kept": kept,
                    "notes": (r.get("notes") or "").strip(),
                    "id": (r.get("id") or "").strip(),
                    "big": False,
                })

        # day-level bounds + label
        d_lat = [p["lat"] for p in tpts] + [c["lat"] for c in cpts]
        d_lon = [p["lon"] for p in tpts] + [c["lon"] for c in cpts]
        bounds = _bounds(d_lat, d_lon)

        # nice label from the first timestamp we can find (UTC getters so it matches the JS clock)
        label = gid
        first_t = tpts[0]["t"] if tpts else (cpts[0]["t"] if cpts else None)
        if first_t is not None:
            label = datetime.fromtimestamp(first_t, tz=timezone.utc).strftime("%a %b %-d")

        # bag weight for this day, if present
        bag = None
        if not weights.empty:
            wsid_col = weights.get("weigh_session_id")
            if wsid_col is not None:
                wrow = weights[wsid_col.astype(str).str.strip() == gid]
                if not wrow.empty:
                    bag = _num(wrow.iloc[0].get("daily_wt_lbs"))

        days.append({
            "id": gid, "label": label, "color": color,
            "track": tpts, "catches": cpts, "bounds": bounds, "bag": bag,
            "stats": _day_stats(tpts, cpts),
        })

    # crown the single biggest measured fish of the whole trip (mutates the shared cpt dict)
    all_catches = [c for d in days for c in d["catches"]]
    measured = [c for c in all_catches if c["len"] is not None]
    big = max(measured, key=lambda c: c["len"]) if measured else None
    if big is not None:
        big["big"] = True

    bags = [d["bag"] for d in days if d["bag"] is not None]
    payload = {
        "title": title,
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "days": days,
        "bounds": _bounds(all_lat, all_lon),
        "fishermen": [{"name": f, "color": fisher_color[f]} for f in fishermen],
        "speed": {"troll": TROLL_SPEED_MPS, "run": RUN_SPEED_MPS},
        "gapSkip": GAP_SKIP_SECONDS,
        "stats": _trip_stats(days, total_distance, total_track_seconds, big,
                             round(sum(bags), 1) if bags else None),
        "quality": {
            "droppedTrack": data.dropped_track_bad + data.dropped_track_acc,
            "droppedTrackBad": data.dropped_track_bad,
            "droppedTrackAcc": data.dropped_track_acc,
            "droppedCatchAcc": data.dropped_catch_acc,
            "droppedCatchNoGPS": data.dropped_catch_nogps,
            "droppedCatchCoord": data.dropped_catch_coord,
            "droppedCatchNoTime": data.dropped_catch_notime,
        },
    }
    return payload


def _num(v):
    if v is None or (isinstance(v, float) and math.isnan(v)) or pd.isna(v):
        return None
    try:
        f = float(v)
        return int(f) if f == int(f) else round(f, 2)
    except (TypeError, ValueError):
        return None


def _len(v):
    """Length in inches, ignoring implausible values so they can't win 'biggest'."""
    n = _num(v)
    if n is None or n < LENGTH_MIN_IN or n > LENGTH_MAX_IN:
        return None
    return n


def _bounds(lats, lons):
    if not lats or not lons:
        return None
    return [[min(lats), min(lons)], [max(lats), max(lons)]]


def _day_stats(tpts, cpts):
    lengths = [c["len"] for c in cpts if c["len"] is not None]
    return {
        "catches": len(cpts),
        "kept": sum(1 for c in cpts if c["kept"]),
        "biggest": max(lengths) if lengths else None,
        "points": len(tpts),
    }


def _trip_stats(days, distance_m, track_seconds, big, bag_total):
    all_catches = [c for d in days for c in d["catches"]]
    lengths = [c["len"] for c in all_catches if c["len"] is not None]
    species, lures = {}, {}
    for c in all_catches:
        species[c["species"]] = species.get(c["species"], 0) + 1
        if c["lure1"]:
            lures[c["lure1"]] = lures.get(c["lure1"], 0) + 1
    return {
        "days": len(days),
        "catches": len(all_catches),
        "kept": sum(1 for c in all_catches if c["kept"]),
        "biggest": max(lengths) if lengths else None,
        "biggestBy": (big["fisher"] if big else None),
        "biggestSpecies": (big["species"] if big else None),
        "miles": round(distance_m / 1609.344, 1),
        "hours": round(track_seconds / 3600.0, 1),
        "topSpecies": sorted(species.items(), key=lambda kv: -kv[1]),
        "topLure": (sorted(lures.items(), key=lambda kv: -kv[1])[0][0] if lures else None),
        "bagTotal": bag_total,
    }


# --------------------------------------------------------------------------------------
# Render
# --------------------------------------------------------------------------------------

TEMPLATE_PATH = Path(__file__).with_name("replay_template.html")


def render_html(payload: dict) -> str:
    template = TEMPLATE_PATH.read_text(encoding="utf-8")
    # json.dumps defaults to ensure_ascii=True, so non-ASCII (incl. U+2028/U+2029) is already
    # \u-escaped. We only neutralize the ASCII '<' '>' '&' so a literal </script> or a stray
    # '<' in any user field (notes, location) can't truncate the blob and brick the page.
    blob = (json.dumps(payload, separators=(",", ":"))
            .replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026"))
    html = template.replace("/*__PAYLOAD__*/null", blob)
    html = html.replace("__TITLE__", _escape(payload["title"]))
    return html


def _escape(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------

def _slug(s: str) -> str:
    return "".join(c if c.isalnum() or c in "-_" else "-" for c in s).strip("-") or "trip"


def find_export_dirs(parent: Path) -> list[Path]:
    """A folder is an export if it has catches.csv or track.csv."""
    dirs = []
    if (parent / "catches.csv").exists() or (parent / "track.csv").exists():
        dirs.append(parent)
    for child in sorted(parent.iterdir()):
        if child.is_dir() and (
            (child / "catches.csv").exists() or (child / "track.csv").exists()
        ):
            dirs.append(child)
    seen, out = set(), []
    for d in dirs:
        if d not in seen:
            seen.add(d); out.append(d)
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build a fishing trip replay map.")
    ap.add_argument("path", help="export folder (or parent with --all)")
    ap.add_argument("--all", action="store_true",
                    help="stitch every export subfolder under PATH into one replay")
    ap.add_argument("-o", "--out", help="output .html path")
    ap.add_argument("-t", "--title", help="map title")
    args = ap.parse_args(argv)

    root = Path(args.path).expanduser().resolve()
    if not root.exists():
        sys.exit(f"path not found: {root}")

    if args.all:
        dirs = find_export_dirs(root)
        if not dirs:
            sys.exit(f"no export folders (catches.csv/track.csv) found under {root}")
        loaded = merge_loaded([load_export(d) for d in dirs])
        default_title = f"{root.name} — {len(dirs)} day(s)"
        default_out = root / "replay_all.html"
    else:
        loaded = load_export(root)
        if loaded.track.empty and loaded.catches.empty:
            sys.exit(f"no usable data in {root} (need catches.csv and/or track.csv)")
        default_title = root.name
        default_out = root / f"replay_{_slug(root.name)}.html"

    title = args.title or default_title
    payload = build_payload(loaded, title)

    if not payload["days"]:
        sys.exit("nothing to plot after quality filtering — check the export files.")

    out = Path(args.out).expanduser().resolve() if args.out else default_out
    out.write_text(render_html(payload), encoding="utf-8")

    s = payload["stats"]
    q = payload["quality"]
    print(f"✓ {out}")
    print(f"  {s['days']} day(s) · {s['catches']} catch(es) · "
          f"{s['miles']} mi · {s['hours']} hr on the water"
          + (f" · {s['bagTotal']} lb bag" if s["bagTotal"] is not None else ""))
    if s["biggest"]:
        print(f"  biggest: {s['biggest']}\" {s['biggestSpecies'] or ''} "
              f"by {s['biggestBy'] or ''}".rstrip())
    notes = []
    if q["droppedTrackAcc"]:
        notes.append(f"{q['droppedTrackAcc']} track pts >{int(ACCURACY_LIMIT_M)}m")
    if q["droppedTrackBad"]:
        notes.append(f"{q['droppedTrackBad']} bad track rows")
    if q["droppedCatchAcc"]:
        notes.append(f"{q['droppedCatchAcc']} low-acc catches")
    if q["droppedCatchNoGPS"]:
        notes.append(f"{q['droppedCatchNoGPS']} catches w/o GPS")
    if q["droppedCatchCoord"]:
        notes.append(f"{q['droppedCatchCoord']} catches w/ bad coords")
    if q["droppedCatchNoTime"]:
        notes.append(f"{q['droppedCatchNoTime']} catches w/o time")
    if notes:
        print("  filtered: " + ", ".join(notes))
    print(f"  open it: open '{out}'")


if __name__ == "__main__":
    main()
