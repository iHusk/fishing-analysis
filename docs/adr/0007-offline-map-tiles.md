# ADR 0007 — Offline map tiles & the depth-contour boundary

- **Status:** Accepted (direction); implementation deferred
- **Date:** 2026-06-23
- **Deciders:** Tyler (project owner)
- **Linear:** APP-7 / HAY-148 (map home), APP-8 / HAY-149 (tile spike), STRAT-1 / HAY-138 (premium)

## Context

The phone app is **fully offline on the water** (no cell coverage on Lake Oahe). The owner
wants to explore a **map home screen** (ANGLR-style: waypoints + a corner "Log Catch"
button), which requires map tiles that work with **zero connectivity**. The open questions
were: how does a user pre-download a tile pack for a lake, is it free or paid, and what's the
legal/technical shape? A research spike (Perplexity + official docs, captured in HAY-149)
answered these.

Key findings:
- **OSM.org tiles forbid bulk download**; Apple/Google/Bing/Esri **satellite cannot be
  legally cached offline** for a third-party app.
- **Protomaps / PMTiles** (a single open file built from OpenStreetMap) is purpose-built for
  offline and is **free**. **USDA NAIP** aerial (US, ~0.6 m, public domain) and **Sentinel-2**
  (global, free) are legal, cacheable satellite sources.
- **Bathymetry is the gap:** no free GIS depth contours exist for most lakes (incl. Oahe);
  the good data (Navionics, Humminbird LakeMaster) is **paid and non-exportable** into our app.

## Decision

1. **App stays logging-first.** The map is a future feature, not v1 of the phone app; the
   Tape-Wheel catch entry (ADR 0006) is the priority.
2. **When we build the map, use a free, self-hosted/bundled stack:** **MapLibre + PMTiles**
   (OSM street basemap) **+ NAIP** satellite (tiled by us), bundled or first-launch-downloaded
   on device. No commercial tile provider (MapTiler/Mapbox) and no Apple/Google/Bing/Esri
   offline tiles. Attribution: "© OpenStreetMap contributors."
3. **"Download a lake" = per-lake tile pack by bounding box.** Generalizes to any lake; for a
   handful of personal lakes, bundle at build or download once on first launch (do **not**
   build a "download from a hosted provider" UI — it violates bulk-download policies).
4. **Resolution scales to lake size via an adaptive maxzoom.** Imagery should be fairly
   high-res, but tile count grows ~4× per zoom level, so a large reservoir like Oahe at full
   native res (~z18) balloons to GBs. The download flow derives **maxzoom from lake extent +
   a per-pack storage budget** — small lakes go higher-zoom, large lakes cap lower (or warn).
5. **v1 map = "just show the map" (street + satellite). Depth contours are deferred** and are
   a **candidate premium/paid feature** (since free contours don't exist and the good data is
   paid + non-exportable). The base map stays free.

## Consequences

- ✅ Offline maps can be **$0 recurring** and fully legal for street + satellite.
- ✅ Clear monetization boundary: base map free, **bathymetry as a paid tier** if we productize.
- ✅ Logging-first keeps near-term focus on the catch-entry build.
- ⚠️ We must **tile NAIP imagery ourselves** (gdal2tiles → MBTiles/PMTiles) and host/bundle the
  packs — a real data-pipeline + storage task.
- ⚠️ iOS rendering needs MapLibre Native + a small PMTiles HTTP shim (or MapLibre GL JS in a
  WKWebView) — an integration to prototype.
- ⚠️ Free Oahe **bathymetry** is best-effort only (USACE Omaha District surveys, variable
  quality); otherwise depth maps wait for a paid-data path.

## Alternatives considered

- **Commercial providers (MapTiler $25–295/mo, Mapbox MAU billing):** rejected for a personal
  app — unnecessary cost when open data + PMTiles is free.
- **Apple MapKit / Google / Bing / Esri offline tiles:** not legally available for offline
  caching in a third-party app.
- **Navionics / LakeMaster as a data source:** rejected — paid and non-exportable; usable only
  as separate reference apps. Informs the "depth contours = premium" decision.
- **Map in v1 of the phone app:** deferred — logging-first; mapping stays on the laptop web
  tools for now.
