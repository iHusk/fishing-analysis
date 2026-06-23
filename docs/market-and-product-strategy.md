# Market Landscape & Product Strategy

> Durable capture of the 2026-06-22 competitive research + the product-strategy
> conversation that followed. This is a *thinking doc*, not a commitment. Read it
> before deciding whether to ever push this past "a great personal tool."
>
> Research method: four parallel Perplexity research sweeps (competitors/market-size,
> feature inventory, angler sentiment, market trends/positioning). Confidence flags are
> carried through; the dollar *size* of the app market is genuinely uncertain, the
> *growth rate* and the *feature gaps* are the trustworthy findings.

---

## Part 1 — What's already out there

### The players

| App | Scale | Money | Status |
|---|---|---|---|
| **Fishbrain** | ~14M registered, ~800K MAU; markets "20M+" | ~$15M rev (2023), Pro ~$80/yr | Category leader, **but took a down-round 2022–23**; growth normalized, not confirmed profitable |
| **Navionics / Garmin** (ActiveCaptain) | Huge, not disclosed | Chart subs **$50–200/yr** | **Where the real money is** — marine charts + hardware, not logging |
| **C-MAP / Lowrance** (Brunswick) | Not disclosed | Chart subs + hardware | The *other* walled garden |
| **ANGLR** (+ Bullseye BLE button) | Never disclosed | App free, hardware/B2B | **Alive & downloadable, but BUGGY** (owner tested 2026-06-23, "buggier than our v1"). Has animated play/speedup replay, auto water-gauge height, auto weather, cloud map + waypoints, a data-style "wrapped." Bullseye = the two-button rod device we envisioned — **piggyback candidate.** |
| **FishAngler** | Claims 5M | Free + VIP $50/yr | Alive, niche |
| **MyCatch** (Anglers Atlas) | ~13K contributors (old) | Free; **B2B/B2G research-data contracts** | Citizen-science / DNR catch-reporting niche |
| **Fishidy** | Not broken out | Hardware-tethered (Raymarine) | Alive but low-profile (NOT shut down — common myth) |
| Small private/offline tools | tiny | mostly free/one-time | **Fishing Journal: Angler Log**, **Fishz**, **Anglers' Log** — the closest analogs to *our* private-analytics positioning |

### Market economics (the important part)

- **Pure catch-logging is mostly free. Nobody monetizes logging well.** Money in this
  space comes from **(a) map subscriptions, (b) hardware, or (c) selling/serving data to
  agencies** — never from the logbook itself.
- Even Fishbrain, the leader, survives on a **three-legged stool**: Pro subs + a gear
  marketplace + brand/data partnerships. That diversification is the tell that
  subscriptions alone don't carry this niche.
- **Market size:** firms disagree ~10× ($220M vs ~$1.4B). Trustworthy signal = **~9–12%
  CAGR**. TAM is large: **~58M US anglers, 220M+ globally**.
- **Failures are quiet deaths** (no updates for 12–24 months, then delist) — ANGLR is the
  textbook case — not announced shutdowns.

### Where we're genuinely novel — *corrected after hands-on with ANGLR (2026-06-23)*

> **Important correction:** the original sweep undercounted ANGLR. It is **alive,
> downloadable, and feature-rich** (just buggy), with **animated play/speedup replay** and a
> "wrapped"-style summary. So the headline features are NOT unclaimed. The honest thesis
> shifts from *"features nobody has"* to **"feature parity exists — we out-execute on craft,
> data quality, privacy, and analytics depth."** This is a better, more defensible thesis for
> a personal-tool origin (craft beats a buggy incumbent).

| Our feature | Reality after hands-on | Our edge |
|---|---|---|
| Animated satellite trip-replay | **ANGLR has it** (play/speedup) | Ours is smoother / better-looking (owner's direct A/B) |
| "Trip Wrapped" | ANGLR has a data-summary version | Ours leads with a **poster "payoff" visual**; their data goes on a **2nd page** (owner's preferred ordering) |
| Weight-per-inch fish-health analytics | **Still unclaimed** | Genuine differentiator |
| Catch-logging **data fields** | **Ours richer than ANGLR's** | …but **our entry UI needs a full rethink** (Part 3) |
| **Private, on-device** named areas + waypoints | ANGLR has cloud map/waypoints | **Private + on-device** is the wedge |
| Target-species visual emphasis | Novel framing | — |
| **Reliability** | ANGLR is buggy | **"It just works" / craft** is a real moat here |
| Auto water-gauge, auto weather | **ANGLR has these, we don't** | Parity gap to close (Part 3) |
| Offline-first | ANGLR does it too | Table stakes |

**Revised thesis:** we don't win on novelty — competitors reached the headline features. We
win on **execution quality, richer catch data, privacy-by-default, deeper personal
analytics, and a more emotionally satisfying Wrapped payoff.** A craft game — which suits us.

### What anglers actually say

- **Loved:** depth-contour maps (Navionics is the walleye-crowd champ), all-in-one
  bite/weather/solunar, and **effortless one-press logging** (ANGLR's button was the
  most-praised single idea anywhere).
- **Hated:** ① **subscription cost** (Fishbrain Pro = #1 gripe; basic logging shouldn't
  be paywalled), ② **fake/stale hotspots**, ③ **social-feed bloat** ("I want a tool, not a
  fishing Instagram"), ④ **data-lock-in** fear.
- **Spot privacy is the loudest theme.** Fishbrain is branded "*the* spot-burner app."
  Cultural norm: "real fishermen don't post pins." Walleye crowds share *structure
  archetypes* ("transitions in 15–25 ft"), never coordinates.
- **Do serious anglers even log?** Stratified — and **paper + spreadsheets still beat
  apps** for serious folks (fast with wet gloves, battery-free, future-proof, full
  analytical control). Tournament anglers/guides log heavily and guard it like an asset.
- **Biggest unmet wish:** *real analytics on your own history* ("your best smallmouth =
  overcast, SW wind, 60–65°F"), not generic community "AI." **This is exactly our lane.**

### Trends 2024–2026

AI species-ID → auto-regs is becoming table stakes; **AI photo auto-measurement** is the
live battleground (onWater, Fishtechy); **citizen-science data pipes to state DNRs**
(onWater's C.A.T.C.H.) are an emerging partnership moat; hardware ecosystems hardening into
two walled gardens (Garmin/Navionics, Brunswick/C-MAP/Lowrance).

---

## Part 2 — Product strategy & open questions

> Owner's framing (2026-06-22): *"If I could pull an extra $10k/month from an app like
> this, I'd think it was a huge win."* Plus three ideas: anonymize Wrapped so it stays
> viral without burning spots; lean hard into personal / anti-"fish-Instagram"; and make
> logging **effortless** via hardware/voice (Humminbird & other integrations; a velcro-to-
> rod two-button "bite"/"catch" device with voice capture).

### Is $10k/month feasible? (back-of-envelope)

$10k/mo = **$120k/yr**. The path you pick changes the required scale by ~50×:

| Path | Price | Payers needed | Free users implied (at 1–3% conv.) | Read |
|---|---|---|---|---|
| Consumer subscription | $40/yr | ~3,000 | **100k–300k** | Hard — that's real distribution/marketing |
| "Serious angler" tier | $80/yr | ~1,500 | 50k–150k | Hard-ish |
| **Guide/charter B2B** | $150–300/yr | **~400–800** | direct sales, no funnel | **Most feasible** — fewer, higher-value, reachable customers |
| Hardware + attach | $80 device @ ~$30 margin | ~330 units/mo | n/a | Margin-thin but **demand-proving**; bundles a sub |
| One-time unlock | $30 | ~4,000 sales/yr | high churn-free top-funnel | Simple, but no recurring base |

**Honest read:** $10k/mo is *not* crazy, but the consumer-subscription route is the
hardest version of it (you'd be fighting Fishbrain's funnel with no network effect). The
**realistic routes to $10k/mo are the high-ARPU ones**: guides/charters/clubs, or a
hardware+software bundle that proves demand and justifies a recurring tier. The 58M-angler
TAM means even a tiny, well-targeted slice clears $120k/yr — the whole game is *distribution
to the serious niche*, not building more features.

### The Wrapped ↔ spot-burner tension (the key creative problem)

The whole point of Wrapped is virality: someone sees it and goes **"what is that? I need
that!"** But a real satellite track + catch pins **is** a burned spot. These feel opposed.
They're not — because **the thing that makes Wrapped viral is the *format and the brand*,
not the coordinates.** People react to the gorgeous squiggle, the catch constellation, the
stats, the identity ("I'm a 47-walleye summer"). None of that requires a reverse-geocodable
map. So the design rule is: **share the aesthetic, leak zero coordinates.**

Concrete ways to anonymize while keeping the "I need that" hook (cheapest → richest):

1. **De-georeference the shared poster.** Private replay = full satellite (for *you*). The
   *shared* poster drops the basemap entirely and renders the track shape + catches on an
   **abstract/stylized background** (gradient, paper, topo-art) with **no axes, no
   coordinates, no recognizable shoreline**. The shape is still beautiful and personal; it's
   just no longer a map you can drive to. *This alone solves 90% of it.*
2. **Rotate + translate + scale to a neutral frame.** Randomly re-orient and normalize the
   track so even the *relative* geometry can't be matched against a known lake outline.
3. **Name, don't pin.** Our **private named-areas** feature is the secret weapon here: the
   poster can say *"North Flat"* or *"Bob's Landing area"* — a label **you** chose — instead
   of a coordinate. Outsiders see vibe ("they crushed it on the North Flat"), not a location.
4. **Zoom-tier the share.** Offer share granularities: *Off / Lake-level / County-level* —
   never spot-level. Default to the most private.
5. **Stats-forward layouts.** Make the hero of the shareable the **numbers + species +
   identity**, with the map as abstract art, not a usable chart. The map is texture, not data.
6. **Per-share opt-in.** Every share is an explicit choice with a live preview of exactly
   what's visible. Private by default, always.

**Design principle to carry forward:** *the brand/format is the viral payload; the
coordinates are never part of it.* That's how you get "I need that!" without becoming the
next spot-burner app — and it's a positioning wedge **against** Fishbrain, not an imitation
of it.

### Effortless capture — the hardware + voice angle

This is the strongest expansion idea, because it attacks the **#1 reason serious anglers
quit apps and go back to paper: on-the-water friction.** The most-praised feature in *all*
the sentiment research was ANGLR's one-press logging — and ANGLR is **alive but buggy and
not analytics-focused**, so the *execution* lane is wide open even though the hardware exists.

- **Two-button velcro-to-rod device ("bite" / "catch").** Don't build hardware day one —
  **piggyback the existing ANGLR Bullseye** (a BLE button) if its protocol is open enough to
  pair with directly, and wire it to *our* analytics + private-Wrapped instead of their buggy
  app. Press = timestamp + freeze GPS + (optionally) trigger phone voice capture. Build our
  own device only if piggybacking proves impossible. This is **demand-proving** and bundles a
  recurring software tier. (Feasibility of pairing = an open research item, see Part 3.)
- **Voice mode.** Hands-free, wet-glove-friendly: "*18 inch walleye, 22 feet, released*" →
  on-device speech-to-text fills the catch fields. Directly answers the friction complaint.
  Pairs perfectly with the button (button = "I caught one," voice = the details).
- **Read-only hardware import (the realistic first step, no partnership needed).** Import
  **GPX waypoints + sonar logs** from Humminbird (.DAT/.SON), Lowrance/C-MAP, Garmin.
  Position the app as the **"smart analytics layer on top"** of whatever electronics they
  already own — you don't need a vendor SDK to ingest exported files. Deep *live*
  integration needs a partnership; **start with import/export and earn the partnership.**
- **Why this combination is defensible:** effortless capture (button+voice) → richer data →
  better personal analytics → the private-Wrapped payoff. It's a loop competitors don't have
  because they optimize for a public feed, not the individual's data quality.

### Positioning (the throughline)

- **"A tool, not a fishing Instagram."** This is the play. Anti-feed, anti-paywalled-basics,
  pro-privacy, pro-your-own-data. It's the inverse of every top complaint about Fishbrain.
- **Privacy is the moat we *can* hold.** Local-first, your spots never feed a public map,
  first-class CSV/GPX export (turn "data lock-in" fear into a selling point).
- **Win on analytics depth**, because that's the loudest unmet wish and where everyone stops
  at log-and-pins.
- **Highest-ARPU wedge = guides/charters/clubs**, not consumer subscriptions.

### Recommended path (unchanged by this conversation, sharpened)

1. **Use it ourselves for a full 2026–27 season.** It's already a great personal tool.
2. Quietly put it in front of **5–20 serious walleye anglers / a guide or two.** Watch for
   *unprompted repeat use* and "I'd be upset to lose this."
3. **Prototype the de-georeferenced Wrapped share early** — it's cheap (it's a render mode
   we already have most of) and it's the single most testable virality/ethics hypothesis.
4. Only if the signal is real, explore the **button+voice hardware** and the **guide B2B
   tier** — those are the two credible roads to $10k/mo. If the signal isn't there, we still
   win: a tailored personal tool, zero support burden.

### Open questions to revisit

- [ ] Does a de-georeferenced Wrapped poster still trigger "I need that"? (Build the render
      mode, test on 5 people.) **Cheapest highest-value experiment.**
- [ ] What sonar/waypoint export formats do Humminbird/Lowrance/Garmin actually emit, and
      how clean is the import? (Spike: parse one real `.DAT`/GPX.)
- [ ] Is the BLE two-button device a buildable nights-and-weekends thing (off-the-shelf BLE
      button + firmware) or a real hardware project?
- [ ] Voice mode: on-device (private, offline — fits our ethos) vs. cloud accuracy.
- [ ] Guide/charter discovery: would one local guide pay $150/yr for client-trip logs +
      pattern analytics? (One customer-development conversation answers this.)

---

## Part 3 — Field notes from using ANGLR (2026-06-23)

Owner installed and used the live ANGLR app. Raw observations + the TODOs they imply. These
are the most valuable competitive signal we have — direct hands-on beats any web research.

### What ANGLR does that we should match (parity gaps)

| Their feature | Why it matters | Our action |
|---|---|---|
| **Animated GPS replay** w/ play + speedup | Confirms the format resonates | We already have it, and **ours is better** — keep that edge |
| **Auto water-gauge height** | "super nice and needed" — river stage drives the bite | **Add auto stage-height capture** (USGS site for Oahe/Missouri R. — research underway) |
| **Auto weather recording** | Conditions-at-catch without typing | **Auto-log weather** at catch/trip (NWS / Open-Meteo — research underway) |
| **Weather alerts** | Safety + planning | **Add weather alerts** (NWS active-alerts — research underway) |
| **Map with user-set waypoints** | Genuinely useful on the water | **Tap-to-add waypoints, kept PRIVATE on-device** — "would be pretty badass." Their full map is a bit *overkill*; we do a lean, private version |
| **Bullseye two-button device** | Exactly the effortless-capture idea | **Piggyback their hardware to start** (research: is the BLE protocol open?) |

### Where WE are already better (protect these)

- **Catch-entry data fields are richer than ANGLR's** — keep the fields + "bait used."
- **Replay quality** — smoother, better-looking than theirs.
- **Reliability** — *"trying to get the ANGLR app to work is tricky at best… very buggy,
  more buggy than my initial app."* **"It just works" is a real differentiator.** Don't lose it.
- **Wrapped ordering** — theirs is data-only. **Ours should lead with the cool poster
  "payoff" visual, then a 2nd page with the cool data** (their data view is a good 2nd-page
  reference).

### The big app-side TODO: catch-entry UI needs a full rethink

> Owner: *"our UI for entering this data just isn't good enough in its current state… Needs
> a full rethinking. I like the fields and the bait used."*

The **fields are right; the entry experience is wrong.** Specific asks:
- **Trip-level defaults** — set defaults once per trip so every catch inherits them.
- **Per-angler locked defaults** — when an angler is selected, lock in *their* defaults
  (their rod/reel/bait/boat-seat etc.) so logging is near-instant.
- Pair this with the **voice + two-button capture** path so on-the-water logging is effortless.
- This is a **full UX redesign of `CatchEntryView`**, not a tweak. Worth a design pass
  (defaults model, angler profiles, fast-path entry) before building.

### Brand-partnership question (owner asked directly)

> *"The Abu Garcia smart rod shows there's likely a path to partnering with a brand. Do
> these result in me making more money with a licensing deal?"*

Open — being researched this turn (smart reels/rods ecosystem + whether licensing actually
pays a small developer). Findings + verdict to be appended below.

### New research items kicked off (2026-06-23)

- [ ] **Smart reels/rods 2026** (Ardent Outdoors list, Abu Garcia smart rod) — who's
      app-connected, any open SDK/BLE to read?
- [ ] **Does a brand licensing/partnership deal actually make money** for a tiny app, or is
      it a distraction from the $10k/mo goal? (deal structures, real examples)
- [ ] **ANGLR Bullseye piggyback feasibility** — generic BLE button vs. locked to their app?
- [ ] **Auto water-gauge** — exact USGS site number(s) for Lake Oahe / Oahe Dam / Missouri R.
      at Pierre + the instantaneous-values endpoint.
- [ ] **Auto weather + alerts** — NWS / Open-Meteo endpoints, offline caching strategy.
- [ ] **CatchEntryView full redesign** — trip defaults + per-angler locked defaults + fast-path.
- [ ] **Private on-device waypoint map** — tap-to-add, never leaves the device.

### Research findings (2026-06-23)

**① Bullseye piggyback — DON'T. Use a generic BLE button instead.**
The ANGLR Bullseye is **proprietary and locked to the ANGLR app** — no public BLE GATT spec,
no SDK, bundled with ANGLR Pro (was $29.99 standalone). A 3rd-party app could only read it by
reverse-engineering BLE packets — fragile, breaks on firmware updates, bad foundation.
**Verdict: if we want a physical bite/catch button, use an off-the-shelf BLE button we
control (define our own GATT), not the Bullseye.** Good news from the other research thread:
**CoreBluetooth can pair with a generic BLE button with no manufacturer SDK** — `CBCentralManager`
+ `setNotifyValue` on a vendor characteristic (prefer a custom GATT char over HID-keyboard
buttons, which iOS captures at the OS level). Needs `bluetooth-central` background mode +
`NSBluetoothAlwaysUsageDescription`. So a DIY two-button device is genuinely buildable.

**② Brand licensing — mostly a distraction at our scale. Skip it for now.**
- There's **no mainstream connected smart reel/rod with an open SDK** in 2026. The "Abu Garcia
  smart rod" appears to be concept/prototype chatter, **not a shipping product**. Real "smart"
  data lives in separate accessory devices (castable sonar, cast trackers), all closed apps.
- **Who pays whom?** For a tiny app, usually **nobody pays you** — you integrate their free SDK
  for exposure, or *you* pay to use their branding. Cash flows to you only via (a) a paid
  **white-label/contract build** (that's consulting, not passive licensing) or (b) a rare
  guaranteed annual license. Typical structures (~$0.5–5/device or ~$0.5–2/MAU) need
  **5,000 devices/mo or 10,000 MAU** through one partner to hit $10k/mo — niche fishing
  hardware rarely moves that, and when it does the brand has its own app (see Fishbrain, ANGLR).
- **Verdict:** don't chase a tackle-brand deal as the $10k/mo path. The faster paths are
  **our own paid app (~2,000 subs @ $5/mo), B2B guides/clubs (~100–200 @ $20–50/mo), and
  tackle affiliate links off logged catches.** Revisit hardware partnerships only with leverage
  (thousands of engaged paying users). Only worth taking: a paid fixed-scope white-label build,
  or a zero-lock-in free integration run as a growth experiment with a kill-switch.

**③ Auto water-gauge — endpoints confirmed live (free, no key):**
- **River stage / tailwater:** USGS site **`06440000` "Missouri River at Pierre, SD"** (Pierre
  is just below Oahe Dam = effectively the tailwater). *(Note: a first lookup wrongly returned
  `06478000` — that's the James River, 80 mi away. Don't use it.)*
  `https://waterservices.usgs.gov/nwis/iv/?sites=06440000&parameterCd=00065,00060&format=json`
  (`00065`=gauge height ft, `00060`=discharge cfs; data flagged provisional "P").
- **Reservoir POOL elevation** (the lake surface itself — USGS doesn't cover it): **USACE CWMS
  Data API**, office `NWDM`, timeseries `OAHE.Elev.Inst.1Hour.0.Best-MRBWM` (verified live:
  pool ≈ 1598.27 ft NGVD-29). Tailwater: `OAHE-Tailwater.Elev.Inst.1Hour.0.Best-MRBWM`.
  `https://cwms-data.usace.army.mil/cwms-data/timeseries?office=NWDM&name=<id>&begin=…&end=…`
  with header `Accept: application/json;version=2`.

**④ Auto weather — confirmed live (free, no key):**
- **Open-Meteo (primary, one call incl. barometric pressure):**
  `https://api.open-meteo.com/v1/forecast?latitude=44.3731&longitude=-100.3675&current=temperature_2m,relative_humidity_2m,pressure_msl,surface_pressure,wind_speed_10m,wind_direction_10m,weather_code&temperature_unit=fahrenheit&wind_speed_unit=mph`
- **NWS (secondary/observations, needs a `User-Agent` header):** `points/{lat,lon}` → grid →
  `stations/{id}/observations/latest`.
- **Offline:** cache last fetch + timestamp; attach nearest cached obs to each catch with a
  "stale by N min" flag; back-fill when network returns.

**⑤ Weather alerts:** `https://api.weather.gov/alerts/active?point=44.3731,-100.3675`
(GeoJSON; `severity`/`urgency`/`headline`/`expires`). Poll every ~5–10 min while foregrounded,
dedupe on `id`, optionally filter Severe/Extreme. **No push without our own server + APNs** —
for a personal app, foreground polling + local notifications is the workable path.
