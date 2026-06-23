# ADR 0002 — Hybrid web stack: static views + one tiny authoring server

- **Status:** Accepted
- **Date:** 2026-06-21
- **Deciders:** Tyler (project owner)

## Context

This is a **personal** project, used **occasionally** and often **offline at camp**.
It has two kinds of pages with very different needs:

- **Read-only views** (trip replay, analytics) — looked at, never edited. They must
  open from a file with no server running and survive being copied to a phone.
- **Authoring tools** (the lake-area polygon editor, the trip-notes editor) — they
  need a **save path**, i.e. something that can write a file back to disk.

The data already lives in files: `fishing-trip.xlsx`, the app's `exports/**/*.csv`,
`areas/areas.geojson`, and per-trip `*.json` sidecars. Those files are the **single
source of truth**. Standing up a database would create a **competing copy** of that
sacred data and a sync problem nobody asked for.

## Decision

Run a **hybrid stack** with no framework and no database:

1. **Read-only views are self-contained static HTML.** `replay_trip.py` /
   `build_analytics.py` generate single `.html` files that inline their data and pull
   only **CDN libraries** (no build step, no bundler). They open by double-click and
   work offline.
2. **Authoring tools are served by ONE single-file FastAPI app** (`server.py`). It
   binds to **`127.0.0.1` only**, serves `map-areas.html` / `notes.html`, and exposes
   `POST/GET /areas` and `POST/GET /notes`. Every save is an **atomic write** (temp
   file in the same dir + `os.replace`), and it **refuses** to write `*.csv` / `*.xlsx`
   as a belt-and-suspenders guard.
3. **A `justfile` fronts every command** (`just replay`, `just areas`, `just notes`,
   `just analytics`, `just ingest`, `just test`), so the host/port and `uv` invocations
   live in one place.

Files remain the **single source of truth**; nothing is duplicated into a store.

## Consequences

- ✅ Replay/analytics pages need **zero infrastructure** to view — open the file, on
  any machine, with no network.
- ✅ Exactly one process (`server.py`) can ever write, it's localhost-only, and it
  physically cannot clobber the source spreadsheet or CSV exports.
- ✅ The `justfile` is the single, discoverable entry point; no README archaeology to
  remember how to run a thing.
- ⚠️ Authoring requires the server to be running (`just areas` / `just notes`); the
  editors are not usable as bare static files.
- ⚠️ Generated views inline their data, so re-running the generator is the way to
  "refresh" — there is no live binding from page to source.

## Alternatives considered

- **All-static (no server at all):** rejected — the area and notes editors would have
  **no save path**; you can draw a polygon but never persist it.
- **Django + a database:** rejected — overkill for occasional personal use, and the DB
  becomes a **second source of truth** that competes with the sacred files and must be
  kept in sync.
