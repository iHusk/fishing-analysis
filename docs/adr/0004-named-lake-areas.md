# ADR 0004 — Named lake areas

- **Status:** Accepted
- **Date:** 2026-06-21
- **Deciders:** Tyler (project owner)

## Context

Catches carry a lat/lon, but raw coordinates aren't how anyone thinks about a lake — we
think in **named spots** ("the dam face", "the flats"). We want to **label every catch**
with the named area it falls in, use those labels in the replay and analytics, and
eventually show them in the **iOS app**. Constraints:

- The set of areas is hand-drawn and **evolves**, so it needs an editor, not hard-coded
  coordinates.
- The labeling code runs inside the **build step** and must stay light — no heavy geo
  stack to install.
- The phone app must keep working **offline on the water**, where there is no server.

## Decision

1. **Draw areas in a web polygon editor.** `map-areas.html` (served by `server.py`,
   ADR 0002) lets you draw named polygons and saves them as a single GeoJSON
   FeatureCollection at **`areas/areas.geojson`** — every feature requires a
   `properties.name`.
2. **Label with pure-Python point-in-polygon.** `areas.py` implements a **ray-casting**
   (even-odd) point-in-polygon test using **only the standard library — NO shapely** —
   handling Polygon, MultiPolygon, and holes. `assign_area(lat, lon)` returns the first
   containing area's name (or `None`), and it's cached so a build loop doesn't re-read
   the file. This labels catches for both the **replay** and **analytics**.
3. **The iOS app ingests the geojson LATER (phase C) by bundling it at build time.** The
   app will read a copy of `areas.geojson` **bundled into the app at build** (with an
   optional Files import to refresh it) — **never a live connection to `server.py`**.

## Consequences

- ✅ Areas are editable by a human in a map UI; the analysis just re-reads
  `areas/areas.geojson`.
- ✅ The labeler has **no third-party dependency** — it runs anywhere `uv` can run
  Python and stays embeddable in the build.
- ✅ The phone keeps a **bundled** copy, so area labels work with **no network** on the
  water.
- ⚠️ The bundled geojson can go **stale** relative to the editor until the app is
  rebuilt (or a fresh file is imported via Files).
- ⚠️ Ray-casting boundary behavior is exact-but-simple: a point inside a **hole** counts
  as outside the area, and the **first** matching polygon wins if areas overlap.

## Alternatives considered

- **shapely / a geo library for point-in-polygon:** rejected — a heavy dependency for a
  job a few dozen lines of stdlib do, and it complicates embedding in the build and the
  app.
- **A live server connection from the iOS app:** rejected — it would break the hard
  **offline-on-the-water** requirement; bundling the file at build time is the only
  thing that always works.
- **Hard-coded area coordinates in source:** rejected — the area set evolves; it needs a
  drawing tool, not edits to code.
