"""Authoring-tools server for fishing-analysis (INFRA-1 / HAY-119).

A SINGLE-FILE FastAPI app that serves ONLY the authoring tools (area editor,
trip-notes editor). Replay + analytics remain generated static HTML; this server
never generates them. Files are the source of truth -- there is NO database.

Endpoint contract (depended on by WEB-2 / DATA-2):

  POST /areas
    body: a GeoJSON FeatureCollection
      - { "type": "FeatureCollection", "features": [ { ..., "properties": {"name": ...} }, ... ] }
    validation: type must == "FeatureCollection"; every feature must have
      properties.name. On success, atomically writes <root>/areas/areas.geojson.
    returns: { "ok": true, "path": "<written path>", "count": <n features> }

  GET /areas
    returns: the current areas/areas.geojson, or an empty FeatureCollection
      ({ "type": "FeatureCollection", "features": [] }) if absent.

  POST /notes
    body: { "trip": "YYYY-MM", "review": <any>, "days": { ... } }
      - <year> is derived from trip ("2026-06" -> 2026).
    on success, atomically writes <root>/exports/<year>/trip_notes.json.
    returns: { "ok": true, "path": "<written path>", "year": <year> }

  GET /notes?year=YYYY
    returns: that exports/<year>/trip_notes.json, or an empty skeleton
      ({ "trip": null, "review": null, "days": {} }) if absent.

  GET /
    serves map-areas.html if present at repo root, else a short placeholder
    page listing the endpoints. Also statically serves any *.html at repo root.
    404s gracefully for missing files.

Safety invariants:
  - Bound to 127.0.0.1 ONLY (see __main__ / justfile).
  - NEVER writes exports/**/*.csv or fishing-trip.xlsx.
  - All writes are atomic (temp file in the same dir + os.replace).
  - Output root is overridable via FISHING_DATA_ROOT so tests can use a tmp dir.
"""

from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse

# Repo root = directory containing this file. Static HTML is served from here.
REPO_ROOT = Path(__file__).resolve().parent

EMPTY_FEATURE_COLLECTION: dict[str, Any] = {"type": "FeatureCollection", "features": []}
EMPTY_NOTES: dict[str, Any] = {"trip": None, "review": None, "days": {}}


def data_root() -> Path:
    """Output root for generated files. Overridable via FISHING_DATA_ROOT (tests)."""
    override = os.environ.get("FISHING_DATA_ROOT")
    return Path(override).resolve() if override else REPO_ROOT


def areas_path() -> Path:
    return data_root() / "areas" / "areas.geojson"


def notes_path(year: int) -> Path:
    return data_root() / "exports" / str(year) / "trip_notes.json"


def _atomic_write_json(target: Path, payload: Any) -> None:
    """Write JSON atomically: temp file in the same dir, then os.replace.

    Refuses to write anything ending in .csv or any .xlsx, as a belt-and-suspenders
    guard against ever clobbering source data.
    """
    suffix = target.suffix.lower()
    if suffix == ".csv" or suffix == ".xlsx":
        raise HTTPException(status_code=400, detail=f"refusing to write protected file type: {target.name}")

    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        dir=str(target.parent), prefix=f".{target.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_name, target)
    except BaseException:
        # Clean up the temp file on any failure; never leave litter behind.
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass
        raise


def _year_from_trip(trip: Any) -> int:
    """'2026-06' -> 2026. Accepts 'YYYY' or 'YYYY-...' forms."""
    if not isinstance(trip, str) or not trip.strip():
        raise HTTPException(status_code=400, detail="'trip' must be a non-empty string like 'YYYY-MM'")
    head = trip.strip().split("-", 1)[0]
    if not (len(head) == 4 and head.isdigit()):
        raise HTTPException(status_code=400, detail=f"could not derive a 4-digit year from trip={trip!r}")
    return int(head)


app = FastAPI(title="fishing-analysis authoring tools", version="1.0.0")


# --------------------------------------------------------------------------- areas


@app.post("/areas")
async def post_areas(request: Request) -> JSONResponse:
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="request body must be valid JSON")

    if not isinstance(body, dict) or body.get("type") != "FeatureCollection":
        raise HTTPException(status_code=400, detail="body must be a GeoJSON FeatureCollection (type=='FeatureCollection')")

    features = body.get("features")
    if not isinstance(features, list):
        raise HTTPException(status_code=400, detail="FeatureCollection.features must be a list")

    for i, feat in enumerate(features):
        if not isinstance(feat, dict):
            raise HTTPException(status_code=400, detail=f"feature[{i}] must be an object")
        props = feat.get("properties")
        if not isinstance(props, dict) or not props.get("name"):
            raise HTTPException(status_code=400, detail=f"feature[{i}] must have properties.name")

    target = areas_path()
    _atomic_write_json(target, body)
    return JSONResponse({"ok": True, "path": str(target), "count": len(features)})


@app.get("/areas")
async def get_areas() -> JSONResponse:
    target = areas_path()
    if not target.exists():
        return JSONResponse(EMPTY_FEATURE_COLLECTION)
    try:
        return JSONResponse(json.loads(target.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=500, detail=f"could not read areas.geojson: {exc}")


# --------------------------------------------------------------------------- notes


@app.post("/notes")
async def post_notes(request: Request) -> JSONResponse:
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="request body must be valid JSON")

    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="body must be an object { trip, review, days }")

    year = _year_from_trip(body.get("trip"))

    days = body.get("days")
    if days is not None and not isinstance(days, dict):
        raise HTTPException(status_code=400, detail="'days' must be an object when present")

    target = notes_path(year)
    _atomic_write_json(target, body)
    return JSONResponse({"ok": True, "path": str(target), "year": year})


@app.get("/notes")
async def get_notes(year: int) -> JSONResponse:
    target = notes_path(year)
    if not target.exists():
        return JSONResponse(dict(EMPTY_NOTES))
    try:
        return JSONResponse(json.loads(target.read_text(encoding="utf-8")))
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=500, detail=f"could not read trip_notes.json: {exc}")


# --------------------------------------------------------------------------- static


_PLACEHOLDER = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>fishing-analysis authoring tools</title>
<style>body{font:16px/1.5 system-ui,sans-serif;max-width:46rem;margin:3rem auto;padding:0 1rem}
code{background:#f2f2f2;padding:.1em .35em;border-radius:4px}</style></head>
<body>
<h1>fishing-analysis authoring tools</h1>
<p>map-areas.html not found at the repo root yet (WEB-2). Endpoints available:</p>
<ul>
  <li><code>POST /areas</code> &mdash; write a GeoJSON FeatureCollection to areas/areas.geojson</li>
  <li><code>GET&nbsp; /areas</code> &mdash; read areas/areas.geojson (empty FeatureCollection if absent)</li>
  <li><code>POST /notes</code> &mdash; write exports/&lt;year&gt;/trip_notes.json (year derived from <code>trip</code>)</li>
  <li><code>GET&nbsp; /notes?year=YYYY</code> &mdash; read that trip_notes.json (empty skeleton if absent)</li>
</ul>
</body></html>
"""


@app.get("/", response_class=HTMLResponse)
async def index() -> HTMLResponse:
    candidate = REPO_ROOT / "map-areas.html"
    if candidate.is_file():
        return HTMLResponse(candidate.read_text(encoding="utf-8"))
    return HTMLResponse(_PLACEHOLDER)


@app.get("/{filename}.html")
async def static_html(filename: str) -> FileResponse:
    # Serve any *.html at the repo root only -- no path traversal, no subdirs.
    if "/" in filename or "\\" in filename or ".." in filename:
        raise HTTPException(status_code=404, detail="not found")
    candidate = REPO_ROOT / f"{filename}.html"
    if not candidate.is_file():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(candidate)


if __name__ == "__main__":
    import uvicorn

    # Bound to localhost ONLY. The justfile uses the same host/port.
    uvicorn.run(
        "server:app",
        host="127.0.0.1",
        port=int(os.environ.get("FISHING_PORT", "8765")),
        reload=False,
    )
