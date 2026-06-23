#!/usr/bin/env python3
"""
areas.py — pure-Python lake-area lookup (WEB-3 / PIPE-1).

Loads areas/areas.geojson (a FeatureCollection of named polygons drawn in the
area editor) and answers "which named area is this lat/lon in?" via a ray-casting
point-in-polygon test. NO shapely / geo deps — just the standard library, so it
runs anywhere uv can run Python and stays embeddable in the build step.

    >>> import areas
    >>> areas.assign_area(44.5, -100.4)        # -> "Some Area" or None

GeoJSON note: coordinates are [lon, lat] (x, y) order. Polygons may carry holes
(ring[0] = outer, ring[1:] = holes) and a feature may be a MultiPolygon; both are
handled. A point on a hole's interior counts as outside the area.
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

GEOJSON_PATH = Path(__file__).with_name("areas") / "areas.geojson"


def _point_in_ring(lat: float, lon: float, ring: list) -> bool:
    """Ray-casting (even-odd) test for a point inside a single linear ring.
    `ring` is a list of [lon, lat] pairs (GeoJSON order). The closing vertex
    (first == last) is tolerated; the modulo wrap closes the ring either way."""
    inside = False
    n = len(ring)
    if n < 3:
        return False
    j = n - 1
    for i in range(n):
        xi, yi = ring[i][0], ring[i][1]   # lon, lat
        xj, yj = ring[j][0], ring[j][1]
        # does a horizontal ray at y=lat cross edge (i, j)?
        if (yi > lat) != (yj > lat):
            x_cross = (xj - xi) * (lat - yi) / (yj - yi) + xi
            if lon < x_cross:
                inside = not inside
        j = i
    return inside


def _point_in_polygon(lat: float, lon: float, rings: list) -> bool:
    """A GeoJSON Polygon: rings[0] outer, rings[1:] holes. Inside the outer ring
    and outside every hole."""
    if not rings or not _point_in_ring(lat, lon, rings[0]):
        return False
    for hole in rings[1:]:
        if _point_in_ring(lat, lon, hole):
            return False
    return True


@lru_cache(maxsize=8)
def _load(path: str) -> tuple:
    """Parse the geojson into a tuple of (name, geom_type, coords) once per path.
    Cached so repeated assign_area() calls in a build loop don't re-read the file."""
    p = Path(path)
    if not p.exists():
        return ()
    try:
        gj = json.loads(p.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return ()
    feats = gj.get("features", []) if isinstance(gj, dict) else []
    out = []
    for f in feats:
        if not isinstance(f, dict):
            continue
        name = ((f.get("properties") or {}).get("name") or "").strip()
        geom = f.get("geometry") or {}
        gtype = geom.get("type")
        coords = geom.get("coordinates")
        if not name or not coords or gtype not in ("Polygon", "MultiPolygon"):
            continue
        out.append((name, gtype, coords))
    return tuple(out)


def assign_area(lat, lon, geojson_path: str | Path | None = None):
    """Return the name of the first area polygon containing (lat, lon), else None.
    Returns None for missing/invalid coords or when no geojson is present."""
    try:
        lat = float(lat)
        lon = float(lon)
    except (TypeError, ValueError):
        return None
    path = str(geojson_path) if geojson_path is not None else str(GEOJSON_PATH)
    for name, gtype, coords in _load(path):
        if gtype == "Polygon":
            if _point_in_polygon(lat, lon, coords):
                return name
        else:  # MultiPolygon: list of polygons
            for poly in coords:
                if _point_in_polygon(lat, lon, poly):
                    return name
    return None


if __name__ == "__main__":
    import sys
    if len(sys.argv) >= 3:
        print(assign_area(sys.argv[1], sys.argv[2]))
    else:
        print(assign_area(44.5, -100.4))
