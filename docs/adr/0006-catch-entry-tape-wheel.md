# ADR 0006 — Catch-entry UI: the "Tape Wheel" pattern

- **Status:** Accepted
- **Date:** 2026-06-23
- **Deciders:** Tyler (project owner)
- **Linear:** APP-4 / HAY-133 (In Progress)
- **Artifacts:** `wireframes/claude/tape-wheel.html` (chosen), `wireframes/BRIEF.md`, runner-ups `arc-slider.html` + `confirm-card.html`

## Context

The iOS app's **Log Catch** screen is the most-used surface and the one place friction
costs us — on a moving boat, one-handed, wet/cold gloves, bright-sun glare. The original
screen was a stock SwiftUI `Form` with sections + steppers: the *fields are right* (richer
than ANGLR's, per the market notes), but the *entry experience* was slow, fiddly, and it
**scrolled**. After hands-on time with ANGLR, the owner asked for a full rethink — the #1
reason serious anglers abandon apps for paper is on-water friction.

Two facts shaped the design:
- **Most values repeat** between catches (same angler, lure, similar depth), so the screen
  should open **pre-filled** from per-angler + trip defaults — logging is mostly *confirm +
  adjust*, not *fill from scratch*.
- The owner's recurring rejection across iterations was **visual density** ("it's attacking
  me") and **clutter** — too many fields shown at equal weight.

We ran a broad design exploration (15+ self-contained HTML mockups, screenshot-verified for
no-scroll at 390×844) and converged through several rounds of owner feedback.

## Decision

Adopt the **"Tape Wheel"** pattern for catch entry (`wireframes/claude/tape-wheel.html`):

1. **Pre-filled "confirm + adjust" screen.** Opens populated from per-angler + trip
   defaults; a normal walleye is mostly a confirmation.
2. **Two big momentum-drag measurement tapes are the heroes:**
   - **Length** — snaps **0.25"** (only quarter values; 18.5 → 18.75 → 19), minor tick at
     0.25", taller major at each whole inch, **light labels on whole inches only**.
   - **Depth** — snaps **0.5 ft** (half-feet allowed), minor at 0.5 ft, major at each whole
     foot, light labels on a clean regular cadence. A true sibling of Length (equal ease).
3. **Angler + Species at the top** (angler chips Tyler/Brian/Brent/＋; Species large,
   tap to change).
4. **Calm by default via progressive disclosure** — secondary fields collapse to a single
   quiet value and reveal their picker only on tap:
   - Lure colors → shows **Color 1 + ＋**; the named-color rail opens on tap; ＋ adds slots.
   - Bait → one value ("Crawler"); opens a picker on tap (Crawler/Minnow/Lure/Jig;
     "Lure" later points at a specific lure).
   - Water temp → "Water temp · 64°"; tap expands to a drag slider, then collapses.
5. **Disposition folded into Save = one swipe-to-log bar.** Swipe **right → Keep & Log**,
   **left → Release & Log**. This removes the separate Kept/Released control entirely,
   reclaims space, and lives in the thumb zone.
6. **GPS shows the named area only** ("North Flat"); raw coordinates are dropped from the UI
   (still recorded in data).
7. **Dark, premium instrument aesthetic** with a single amber accent; distinctive type
   (no system fonts).

## Consequences

- ✅ The common case (confirm + nudge length) is a couple of gestures; the screen reads as a
  calm instrument, not a dense form. No scrolling at 390×844 (verified).
- ✅ Depth is now as easy as length — the two spatial facts get equal, large controls.
- ✅ The swipe-to-log bar makes disposition a *byproduct of saving*, removing a whole control
  and matching how the phone is actually held.
- ✅ Progressive disclosure keeps full field breadth without the clutter that got prior
  versions rejected.
- ⚠️ Several interactions are **gesture-based** (momentum tape, swipe-to-log, press-hold
  pickers) — they need real haptics + careful SwiftUI implementation and on-device testing
  to feel right; a static port won't capture the feel.
- ⚠️ The "point at a **specific** lure" flow (beyond color + Crawler/Minnow/Lure/Jig) is
  **not yet designed** — left as a follow-up.
- ⚠️ Requires a new **per-angler + trip defaults model** (angler profiles) that doesn't exist
  yet; the whole pattern leans on good defaults.

## Alternatives considered

- **Arc Slider** (`arc-slider.html`) — length/depth as two arcs in the bottom thumb zone;
  the owner's favorite *ergonomics* and palette. Kept as the strong runner-up; its
  thumb-zone idea informed the swipe-to-log placement.
- **Confirm Card** (`confirm-card.html`) — a calm "read-and-confirm" receipt. Liked, but the
  tapes won as the primary length/depth control.
- **Keypad** (big +/- pads) and **Bump Board** (vertical measuring board) — rejected
  (malformed/awkward and "not my favorite all around," respectively).
- **The original 10 concepts** (grid/chip-board/drum-wheels/voice-first/etc.) — rejected as
  **generic and cluttered**; they showed every field at equal weight. This whole ADR exists
  because that first batch failed the "easy + novel" bar.
- **Auto size-based or voice-only entry** — deferred; voice + a BLE button remain a separate
  effortless-capture track (HW-1 / HAY-135), complementary to this screen.
