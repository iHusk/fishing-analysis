# Trip Notes Schema (`trip_notes.json`) — DATA-2 / HAY-123

Free-text annotations for a trip: one whole-trip **review** plus **per-day notes**.
Authored in `notes.html` (served by `server.py`), persisted as a JSON sidecar that the
analysis/replay pipeline merges over the app-exported day notes.

> Files are the source of truth. There is no database. `trip_notes.json` is a sidecar:
> it is **never** written into `fishing-trip.xlsx` or any `exports/**/*.csv`.

## Location

```
exports/<year>/trip_notes.json
```

`<year>` is derived from `trip` (`"2026-06"` → `2026`). One file per trip-year.

## Format

```json
{
  "trip": "2026-06",
  "review": "Great water. Whitlock turned on Thursday; wind killed Friday.",
  "days": {
    "2026-06-19": "Slow morning, picked up after noon on the points.",
    "2026-06-20": "Best day. Cheyenne arm, bottom-bouncers."
  }
}
```

| Field    | Type                       | Meaning                                                              |
|----------|----------------------------|---------------------------------------------------------------------|
| `trip`   | string `"YYYY-MM"`         | Trip identifier. The year is parsed from its leading 4 digits.      |
| `review` | string or `null`           | Free-text review for the whole trip. `null`/empty = no review.      |
| `days`   | object                     | Map of **`weigh_session_id` → note string**. May be empty (`{}`).   |

- `days` keys are `weigh_session_id` values (e.g. `"2026-06-19"`), matching the
  `weigh_session_id` column in `exports/<year>/<YYYYMMDD>/daily_weights.csv`.
- An absent file reads back as the empty skeleton `{ "trip": null, "review": null, "days": {} }`.

## Server endpoints (in `server.py`, unchanged by DATA-2)

- **`GET /notes?year=YYYY`** → returns `exports/<year>/trip_notes.json`, or the empty
  skeleton if absent.
- **`POST /notes`** with body `{ "trip", "review", "days" }` → atomically writes
  `exports/<year>/trip_notes.json` (year derived from `trip`). Returns
  `{ "ok": true, "path": "<written path>", "year": <year> }`.

Writes are atomic (temp file + `os.replace`) and the server refuses to write any
`.csv`/`.xlsx` target.

## Merge rule (pipeline)

The day-notes shown in analytics/replay come from **two** sources:

1. **App day-notes** — the `notes` column in `daily_weights.csv` (exported from the
   FishingLogger app), keyed by `weigh_session_id`.
2. **Sidecar day-notes** — the `days` map in `trip_notes.json` authored here.

When the pipeline assembles a day's note it merges per `weigh_session_id`:

- Start from the app note (`daily_weights.csv` → `notes`).
- If the sidecar has a **non-empty** note for the same `weigh_session_id`, the
  **sidecar wins** and replaces the app note.
- An empty/whitespace-only sidecar note does **not** override a non-empty app note;
  it is treated as "no opinion."
- **Every override is logged** (e.g. `WARNING merge: day 2026-06-19 sidecar note
  overrides app note`) so source-of-truth conflicts are visible in pipeline output.

The whole-trip `review` has no app-side counterpart; it passes through verbatim.

### Resolution summary

| App note (`daily_weights.csv`) | Sidecar note (`trip_notes.json`) | Result          | Logged? |
|--------------------------------|----------------------------------|-----------------|---------|
| present                        | non-empty                        | sidecar         | yes     |
| present                        | empty / missing                  | app             | no      |
| empty / missing                | non-empty                        | sidecar         | no      |
| empty / missing                | empty / missing                  | empty           | no      |
