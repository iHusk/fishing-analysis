# ADR 0008 — Map-centric home screen (direction)

- **Status:** Proposed (direction set); detailed UX + implementation deferred
- **Date:** 2026-06-26
- **Deciders:** Tyler (project owner)
- **Linear:** APP-7 / HAY-148 (epic) + children HAY-157 (live trail), HAY-158 (download-a-lake),
  HAY-159 (re-home core actions), HAY-136 (waypoints/long-press), HAY-149 (tile spike);
  related HAY-130 (area names), HAY-134 (auto-capture)
- **Builds on:** ADR 0006 (Tape Wheel catch entry), ADR 0007 (offline map tiles)

## Context

Today the app is **logging-first**: `ContentView` is a "Now" screen — a big LOG CATCH button plus
Start/Stop Track, Export, and Weigh-in — and the only rich surface is the Tape Wheel catch entry
(ADR 0006). The catch screen is now in good shape, so the owner wants to evolve the **home into a
map** (ANGLR-style), giving spatial context on the water.

The owner's framing (2026-06-26): the home should show a **map with the boat's trail over time**,
keep **Log Catch** prominent (bottom corner), support **long-press to drop a private waypoint**,
and **re-home the existing actions** (start a trip, start/stop tracking, export, weigh-in) into the
new UX rather than losing them. ADR 0007 already established the offline-tile direction (the map
must work with **zero connectivity** on Lake Oahe).

## Decision

Evolve the home screen to be **map-centric**, as a direction (not yet a detailed design):

1. **The home becomes a map** — offline-capable per ADR 0007 (MapLibre + PMTiles street basemap +
   NAIP satellite; no commercial/Apple/Google/Bing offline tiles).
2. **Live boat trail over time** renders on the map as the day's GPS track accumulates (data already
   recorded in `track.csv`); current position + heading shown; follow/recenter control. (HAY-157)
3. **Log Catch stays the most prominent entry** — a thumb-reachable corner button over the map that
   opens the **Tape Wheel** (ADR 0006), with the existing Undo toast. Its `init(onSaved:)` contract
   is unchanged.
4. **Long-press the map to drop & name a private, on-device waypoint** (HAY-136); pins render on the
   live map. Privacy-by-default (never synced/crowdsourced) is our wedge vs the "spot-burner"
   incumbents.
5. **Re-home the core actions** — start a trip, start/stop tracking, export (`ShareSheet`), and
   weigh-in (`WeighInView`) move into the map UX as a thumb-reachable cluster / sheet / corner
   controls; trust UX (today's count, session, GPS status) stays visible without crowding the map.
   (HAY-159)
6. **Offline tile packs are pre-downloaded per lake** ("download a lake"), resolution scaling to lake
   size via adaptive maxzoom + a per-pack storage budget. (HAY-158, built on the HAY-149 spike)

## Consequences

- ✅ Spatial context on the water; waypoints + trail in one home; Log Catch still one tap away.
- ✅ Reuses settled pieces: the Tape Wheel entry, the locked catch schema, the recorded track.
- ✅ Privacy-by-default waypoints differentiate us; everything works fully offline.
- ⚠️ **Net-new map integration** — MapLibre Native + a PMTiles shim (or MapLibre GL JS in a WKWebView)
   must be prototyped (ADR 0007 flagged this).
- ⚠️ **Gesture budget is tight** — map pan/zoom, long-press-to-pin, the catch-screen swipe, and the
   iOS home-indicator edge all coexist; the recent `defersSystemGestures(on: .bottom)` fix is a
   precedent for resolving system-gesture conflicts.
- ⚠️ **On-water performance + battery** matter (continuous map render + background tracking).
- ⚠️ Waypoints persist in a **separate on-device file** (mirror `AnglerProfileStore` / `profiles.json`);
   the locked catch schema is **not** touched.
- ⚠️ **Depth contours stay deferred** (candidate premium) per ADR 0007 — no free Oahe bathymetry.

## Alternatives considered

- **Keep logging-first, single-screen** — rejected; the owner wants the map as the home for spatial
  context and waypoints. (The catch screen itself stays excellent and is reached from the map.)
- **Third-party map apps (Navionics/Google) for the map layer** — rejected; not offline-cacheable for
  a third-party app, and against the privacy-by-default stance.
- **Ship the map before nailing the UX** — deferred; like the Tape Wheel, this needs a wireframe
  exploration → owner review → SwiftUI, tracked under the HAY-148 epic.

## Status note

This ADR records the **direction**. The concrete layout (how the map, trail, Log Catch, waypoints,
and the re-homed actions compose) is a wireframe-first exploration under **HAY-148** and its children —
the same play that produced the Tape Wheel from ADR 0006.
