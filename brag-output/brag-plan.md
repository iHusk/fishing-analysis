# Brag Plan: FishingLogger

## What is this app?
An offline iOS app one guy (and 2–3 buddies) built to log walleye on Lake Oahe, SD — that
quietly turned into a satellite trip-replay, a Spotify-Wrapped-style trip poster, year-over-year
fish-health analytics, and a 10-way design study for logging a catch in under 5 seconds. It's a
personal fishing app engineered like a startup.

## The angle
Play it as a premium product trailer for something gloriously over-engineered. The hook is the
gap between "we just go fishing" and the absurd amount of tech that's actually running. The humor
comes from the project's real absurdity (Spotify Wrapped... for a fishing trip), delivered
straight and beautiful. Every visual is REAL UI we already rendered — replay map, Wrapped poster,
10 phone mockups, analytics.

## Hook (first 2-3 seconds)
Deep navy, faint satellite of Lake Oahe fading up. One line slams in:
**"Most people just go fishing."** Hold. It sets up the reveal that we did not.

## Key moments (the middle)
- **The satellite replay** — real Lake Oahe imagery, the boat track, live HUD: 17 fish · 6.7 lb
  bag · 109 miles · 21 hours. "We logged every mile."
- **Trip Wrapped** — the portrait poster rises with a glow: "Lake Oahe · Jun 18–20 2026," big
  stats (17 catches · 17″ biggest · 6.7 lb). The punchline beat: *we made fishing have a Wrapped.*
- **Ten ways to log a fish** — the centerpiece. 10 distinct phone mockups fly in one by one,
  then converge on the chosen design. "Ten ways to log a catch. Under five seconds." Shows the
  actual design work.

## Outro / punchline
Black. The **FishingLogger** wordmark slams in (teal). Tagline: **"Your season. Every fish.
Offline."** One bell hit, music fades.

## User flow worth showing
The real product flow, all from rendered UI: **log a catch (10 phone concepts) → see the trip
replay on satellite → get your Trip Wrapped.** Entry → action → payoff. These are the centerpiece
scenes, not marketing cards.

## Tone
- Preset: cinematic
- Creative direction: a premium trailer for one guy's gloriously over-engineered walleye app
- Interpretation: big type, dramatic but clean reveals, confident holds; the wink is in the
  copy, never in the motion. Restrained, trailer-scale, not frantic.

## Format: landscape — 1920x1080
## Duration: ~22 seconds

## Visual identity (from the project)
- Background: #081018 (near-black navy) / panels #0b1118–#172638
- Accent: #20d39b (teal-green)
- Warn/gold: #ffd45a (used for biggest-fish / highlights)
- Text: #f4f8fb; muted #9fb0bf; data in mono
- Display font: system SF / -apple-system, bold, tight tracking
- Body font: system SF
- Strongest visual elements: the satellite replay HUD, the Trip Wrapped poster, the 10 dark phone mockups

## Share copy (draft)
FishingLogger: an offline app I built to log walleye on Lake Oahe — that grew a satellite
trip-replay, year-over-year fish-health analytics, and a Spotify-Wrapped for the trip. Your
season, every fish, off the grid.

## Audio direction
- Role: cinematic support — a steady, clean bed with a low swell into the reveals
- Music: happy-beats-business-moves-vol-12-by-ende-dot-app.mp3 (steady/clean, cinematic)
- Music treatment: in ~0.4s, hold ~0.32 volume, gentle swell into the replay + Wrapped reveals,
  fade under the final logo
- Music cue guidance: bundled preset for vol-12 if present (read cues/<stem>.music-cues.json),
  else detect at composition via `npx hyperframes beats`. Lock 2–3 strong cues: the hook line,
  the Wrapped rise, and the logo slam. Beat-grid the 10 phone arrivals.
- Audio-reactive treatment: subtle; let the hero satellite glow and the Wrapped poster presence
  breathe with RMS/bass. No waveform/equalizer visuals.
- SFX posture: sparse, cinematic — 2–3 big ones (impactBell for hero/logo, impactSoft for
  reveals) + light card sounds on the phone montage. All restrained (0.6–0.75).
- Audio-coupled moments: hook line slam; phone cards arriving one-by-one (card slides); Wrapped
  rise (soft bell); count-up stats; logo slam (bell).
- Restraint rule: no busy SFX over the trailer; let big moments ring; music never above 0.4.

## Storyboard

### Scene 1 — Hook — 3.2s
Deep navy. A faint, slightly zoomed satellite of Lake Oahe drifts up from black. Big bold line
SLAMS in centered: "Most people just go fishing." Holds ~1.4s. A small kicker fades under it:
"We don't." (tiny, muted) right before the cut.
Sequential/interaction: none
Audio intent: low cinematic swell beginning; one soft sub-hit on the line slam
Audio-coupled idea: impact on the hook line; // beat-locked to first strong cue
Music: steady bed, low
Transition mood: dramatic (scale + crossfade) → Scene 2

### Scene 2 — The replay — 4.3s
The real satellite replay (replay.png) scales in to fill the frame, dark glass HUD visible. The
boat-track line is emphasized. Overlay label top-left: "TRIP REPLAY — Lake Oahe." A stat row
ticks up bottom: "17 fish · 6.7 lb bag · 109 miles · 21 hrs." Line: "We logged every mile."
Sequential/interaction: yes — the 4 stats count/tick in one by one
Audio intent: swell resolves; gentle ticks on stats
Audio-coupled idea: counter ticks on the stat row; // beat-grid the 4 stats
Music: bed swells slightly
Transition mood: cinematic crossfade → Scene 3

### Scene 3 — Trip Wrapped — 4.2s
Cut to near-black. The portrait Trip Wrapped poster (wrapped.png) RISES from the bottom with a
soft glow and settles center, tilted to flat. Line above/beside: "Then we gave it a Wrapped."
Big stats read on the poster (17 catches · 17″ biggest · 6.7 lb). This is the wink.
Sequential/interaction: none (poster is the moment); subtle glow breathe
Audio intent: soft bell as the poster lands; warmth
Audio-coupled idea: impactBell/glass on poster settle; // beat-locked to a strong cue
Music: warm, present
Transition mood: soft → Scene 4

### Scene 4 — Ten ways to log a fish — 6.4s
Title line top: "Ten ways to log a catch." then under it "Under five seconds." The 10 dark phone
mockups fly in one by one into a fanned grid (use the 10 shots). Then they push back / dim and
ONE (chip-board) scales up to center, teal-highlighted, with a small caption "the one we're
building." Fast, confident, card sounds per arrival.
Sequential/interaction: yes — 10 phones arrive one-by-one, then converge on the winner
Audio intent: rhythmic light card slides per phone; a soft confirm when the winner lands
Audio-coupled idea: card-slide per phone on the beat grid; chip/confirm on the winner
Music: driving, steady
Transition mood: clean → Scene 5

### Scene 5 — Logo / outro — 3.2s
Black. "FishingLogger" wordmark slams in centered (teal #20d39b), tight tracking. Tagline fades
under: "Your season. Every fish. Offline." Hold on empty space. Music fades.
Sequential/interaction: none
Audio intent: one clean bell on the wordmark; music fades to tail
Audio-coupled idea: impactBell on logo slam; // beat-locked to final strong cue
Music: fade out under logo
Transition mood: final hold

**Music mood for this video:** cinematic (steady, clean, one swell, fade under logo)
**Audio summary:** A clean cinematic bed rises through a hook line, swells into the satellite
replay and the Wrapped poster, ticks lightly through the ten-phone montage, and resolves on a
single bell under the FishingLogger logo.
