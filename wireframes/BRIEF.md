# Design Brief — "Log Catch" Screen Redesign

> Self-contained brief for the catch-entry UI rethink (Linear **HAY-133 / APP-4**).
> Written so anyone unfamiliar with the project can produce wireframes from this alone.

## What this is
**FishingLogger** is an offline iOS (SwiftUI) app a small group (Tyler + 2–3 friends) uses
*from a boat* to log walleye on Lake Oahe, South Dakota. It records each fish + a GPS track;
data exports to CSV for later analysis/replay. The **Log Catch** screen opens the instant you
land a fish — a Log button **freezes your GPS at that tap**. Today it's a stock iOS `Form`
with sections + steppers: functional but slow, fiddly, and it **scrolls**. We want a rethink.

## Use context (drives every decision)
Moving boat • often **one-handed** • wet/cold hands or **gloves** • **bright-sun glare** •
sometimes rough water • **fully offline, no network** • keyboards are slow/error-prone here so
**minimize typing**. Most values **repeat** catch-to-catch (same angler, lure, similar depth)
→ **great defaults are the #1 speed lever.**

## Hard constraints
1. **NO SCROLLING** — the whole screen fits one iPhone (**390×844 pt**, iPhone 14/15).
2. **Capture ALL fields** (breadth is a goal) — keep optional/auto ones out of the way.
3. **Intuitive** — a friend logs a fish in **<5 s** with zero training.
4. **On-water robust** — big targets, high contrast, glare-legible, tolerant of imprecise taps.

## Fields to capture (the data model)
**Tier 1 — every catch, fastest:**
- **Angler** — pick from known list (Tyler/Brian/Brent) or add. *Selecting an angler can load
  THAT person's defaults.*
- **Species** — default **walleye**; pick or add (perch, pike, smallmouth, catfish, drum).
- **Length (in)** — PRIMARY value; 0–60, 0.25" steps; most-adjusted control.
- **Kept vs Released** — boolean.

**Tier 2 — common, quick:**
- **Depth (ft)** — 0–300, 1 ft steps.
- **Lure color 1** & **Lure color 2** — pick known colors / add / none.

**Tier 3 — optional / auto:**
- **Water temp (°F)** — optional number.
- **Bait** — optional short text.
- **Location name** — **auto-filled** from owner-drawn named lake areas via the frozen GPS
  point ("North Flat"); editable.
- **Notes** — optional (in data model; allow it).
- **GPS tag** — **auto-captured & frozen** at open; **display-only** (lat/lon ±accuracy m).

*Auto-stamped, never shown for entry:* id, uuid, timestamps (local+utc), year, trip,
weigh_session_id, lat/lon, gps accuracy, heading.

## New capabilities to design for (HAY-133)
- **Trip-level defaults** — set once per trip, inherited by every catch.
- **Per-angler locked defaults** — pick angler → pre-fills their lure/bait/typical depth.
- **Fast-path** — minimal taps for the common case; advanced fields reachable but never in the way.
- **Future-friendly** to a **two-button BLE device** (bite/catch) + a **voice mode** — leave a
  natural home for a voice/confirm affordance.

## Success criteria per wireframe
1. No scroll/clipping at 390×844.  2. Captures ALL fields.  3. <5 s to log, no training.
4. On-water robust.  5. Genuinely distinct, outside-the-box interaction model.

## Per-concept deliverable
A self-contained **mid-fidelity HTML mockup** in a 390×844 iPhone frame, realistic SD-walleye
sample values (Tyler · walleye · 18.5″ · 22 ft · chartreuse · "North Flat" · kept), opens
offline (no external deps), no scroll, + a short rationale.

## The 10 concept directions
1. Radial speed-dial · 2. Tap-tile dashboard · 3. Voice-first / conversational ·
4. One-field swipe deck · 5. Smart-default summary + two-tap confirm · 6. Drag-the-fish ruler
hero · 7. Parallel drum wheels · 8. Map-centric bottom sheet · 9. Pre-filled chip board ·
10. Watch-style compact glance.

Mockups live alongside this file as `wireframes/<slug>.html`; see `wireframes/index.html` for
the gallery and the judge's ranking in the session notes.
