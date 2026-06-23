#!/usr/bin/env python3
"""
ingest.py — replay-prep pipeline (PIPE-1 / HAY-131).

Reads one day's SOURCE CSVs (durable inputs, never written back), applies the
existing replay cleaning (tz ordering, despike, orphan-trim — all reused straight
from replay_trip.load_export), then *derives* a clean bundle alongside the source:

    build/<trip>/replay_bundle.json

The bundle is an OPTIMIZATION for replay_trip.py's fast path; raw CSVs stay the
authoritative source. Into it we fold the things the front-end shouldn't have to
recompute or rediscover:

  * each catch's `area`        — point-in-polygon vs areas/areas.geojson (areas.py)
  * the star list              — catch UUIDs forced to full emphasis (replay_config.json)
  * trip_notes.json (if any)   — day notes + whole-trip review (absent now -> no notes)

HARD RULES honored: pure-Python point-in-polygon (no shapely); never writes
exports/**/*.csv; build/ is gitignored.

Usage
-----
    uv run --with pandas python ingest.py exports/2026/20260620
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import areas
import replay_trip as rt

REPO = Path(__file__).resolve().parent
CONFIG_PATH = REPO / "replay_config.json"

DEFAULT_CONFIG = {"target_species": ["walleye"], "stars": []}


def load_config() -> dict:
    """Load replay_config.json; create it with defaults if absent. Never overwrite
    a non-default existing file."""
    if not CONFIG_PATH.exists():
        CONFIG_PATH.write_text(json.dumps(DEFAULT_CONFIG, indent=2) + "\n", encoding="utf-8")
        return dict(DEFAULT_CONFIG)
    try:
        cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        cfg = {}
    cfg.setdefault("target_species", list(DEFAULT_CONFIG["target_species"]))
    cfg.setdefault("stars", list(DEFAULT_CONFIG["stars"]))
    return cfg


def _trip_slug(export_dir: Path, loaded: "rt.Loaded") -> str:
    """The bundle lives under build/<trip>/. Prefer the source's `trip` column
    (e.g. '2026-06'); fall back to the export folder name."""
    for df in (loaded.catches, loaded.track):
        if not df.empty and "trip" in df:
            vals = df["trip"].astype(str).str.strip()
            vals = vals[vals != ""]
            if not vals.empty:
                return vals.iloc[0]
    return export_dir.name


def load_trip_notes(year_dir: Path) -> dict:
    """Merge exports/<year>/trip_notes.json if present, else {} (absent now)."""
    path = year_dir / "trip_notes.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return {}


def build_bundle(export_dir: Path, tz_offset: float | None = None) -> dict:
    """Clean the day, attach areas + stars + notes, return the bundle dict."""
    loaded = rt.load_export(export_dir, tz_offset=tz_offset)
    cfg = load_config()
    stars = set(s.strip() for s in cfg.get("stars", []) if isinstance(s, str))

    # year dir = exports/<year>/ (parent of the day folder); trip_notes.json lives there
    year_dir = export_dir.parent
    notes = load_trip_notes(year_dir)

    # Attach an `area` to each cleaned catch (pure-Python ray casting).
    catch_rows = []
    if not loaded.catches.empty:
        for _, r in loaded.catches.iterrows():
            uuid = (r.get("uuid") or "").strip()
            area = areas.assign_area(r.get("lat"), r.get("lon"))
            catch_rows.append({
                "uuid": uuid,
                "id": (r.get("id") or "").strip(),
                "species": (r.get("species") or "").strip(),
                "lat": float(r["lat"]),
                "lon": float(r["lon"]),
                "area": area,
                "starred": uuid != "" and uuid in stars,
            })

    bundle = {
        "schema": 1,
        "trip": _trip_slug(export_dir, loaded),
        "source": str(export_dir),
        "tz_offset": loaded.tz_offset_hours,
        "target_species": cfg.get("target_species", []),
        "stars": sorted(stars),
        "notes": notes,
        "catches": catch_rows,
        "counts": {
            "catches": len(catch_rows),
            "with_area": sum(1 for c in catch_rows if c["area"]),
            "starred": sum(1 for c in catch_rows if c["starred"]),
        },
    }
    return bundle


def write_bundle(bundle: dict) -> Path:
    out_dir = REPO / "build" / bundle["trip"]
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "replay_bundle.json"
    tmp = out.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(bundle, indent=2) + "\n", encoding="utf-8")
    tmp.replace(out)   # atomic
    return out


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        sys.exit("usage: ingest.py <export_dir>  (e.g. exports/2026/20260620)")
    export_dir = Path(argv[0]).expanduser().resolve()
    if not export_dir.exists():
        sys.exit(f"path not found: {export_dir}")

    bundle = build_bundle(export_dir)
    out = write_bundle(bundle)
    c = bundle["counts"]
    print(f"✓ {out}")
    print(f"  trip {bundle['trip']} · {c['catches']} catch(es) · "
          f"{c['with_area']} with area · {c['starred']} starred"
          + (f" · notes merged" if bundle['notes'] else ""))


if __name__ == "__main__":
    main()
