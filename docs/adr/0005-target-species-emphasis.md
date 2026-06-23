# ADR 0005 — Target-species emphasis

- **Status:** Accepted
- **Date:** 2026-06-21
- **Deciders:** Tyler (project owner)

## Context

A trip's track logs **every** catch — walleye, but also catfish, drum, and perch. The
replay is a **walleye story**, though, and the by-catch should not compete with it for
attention. Two needs follow:

- The set of species we care about should be **configurable** (some trips we'd want to
  feature smallmouth, say), not hard-coded to walleye.
- Occasionally a **single** off-target fish is a genuine trophy worth featuring, and we
  want to promote that **one catch** without promoting its whole species.

An earlier instinct was to auto-promote any large fish by size, but that fires on
non-target species we don't actually want to spotlight.

## Decision

1. **Configurable target species (multiselect).** `replay_config.json` carries
   `target_species`, defaulting to `["walleye"]`. The replay treats those species as the
   emphasized set; everything else renders as a **smaller / dimmer** glyph. A
   missing/broken config degrades gracefully to the walleye default.
2. **Manual per-catch STAR override instead of size-based promotion.** There is **no**
   automatic size-based promotion. A **`stars`** sidecar list of catch **UUIDs** in
   `replay_config.json` (augmentable per-trip from the bundle) force-highlights a one-off
   trophy, so a single off-target fish can shine without elevating its species.
3. **Crown + heatmap respect the target+starred set.** The crowned "biggest of the trip"
   plus the heatmap weighting both treat a catch as emphasized when it is a target
   species **or** starred (`c.big || c.starred || c.isTarget !== false`), with a toggle
   to show all.

## Consequences

- ✅ The replay reads as a focused story about the species that matter, with by-catch
  present but quiet.
- ✅ Re-targeting is a **config edit** (`target_species`), not a code change.
- ✅ A genuine one-off trophy can be spotlighted **deterministically** by UUID, with no
  risk of size-based false promotions.
- ⚠️ Stars are kept **by catch UUID**, so a star is only as stable as the UUID it points
  at; a re-logged catch with a new UUID drops its star.
- ⚠️ Old payloads with no `isTarget` flag are treated as **emphasized** (fail-open), so a
  pre-feature export shows everything rather than hiding by-catch.

## Alternatives considered

- **Automatic size-based promotion** (highlight any fish over a length/weight threshold):
  rejected — it spotlights large **non-target** species we don't want to feature, and a
  threshold is a poor proxy for "this one mattered."
- **Hard-coding walleye as the only featured species:** rejected — the emphasis set needs
  to be a per-config decision (`target_species` multiselect).
