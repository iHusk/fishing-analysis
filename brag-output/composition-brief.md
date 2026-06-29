# Hyperframes Composition Brief: FishingLogger

## Objective
A ~22s cinematic launch-style brag video for FishingLogger, built entirely from real rendered UI.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: ~22s

## Source Material
- Project root: /Users/thayes-mac/Documents/GitHub/fishing-analysis
- Real UI assets (already rendered) in `assets/img/`:
  - `replay.png` — satellite trip-replay with HUD (landscape)
  - `wrapped.png` — Trip Wrapped poster (portrait 1080x1350)
  - 10 phone mockups: radial-dial, ruler-hero, voice-first, tile-dashboard, drum-wheels,
    map-sheet, swipe-deck, summary-confirm, watch-compact, chip-board (portrait phone frames)
  - `analytics.png` — analytics charts (unused unless room)
- Product name: FishingLogger
- Tagline / strongest claim: "Your season. Every fish. Offline."
- Copy that must appear verbatim:
  - "Most people just go fishing."
  - "Lake Oahe"
  - "Then we gave it a Wrapped."
  - "Ten ways to log a catch."  /  "Under five seconds."
  - "FishingLogger"  /  "Your season. Every fish. Offline."

## Creative Direction
- Tone preset: cinematic
- Creative direction: a premium trailer for one guy's gloriously over-engineered walleye app
- Interpretation: big type, dramatic-but-clean reveals, confident holds; the wink lives in the
  copy, never the motion. Trailer-scale, not frantic.
- Hook: faint Lake Oahe satellite rises from black; "Most people just go fishing." slams in.
- Outro: "FishingLogger" wordmark slam + tagline, music fades.
- Avoid: generic SaaS language, abstract filler, redesigning the real UI.

## Visual Identity
- Background: #06090d / #081018, panels #0b1118–#172638
- Accent: #20d39b (teal-green); gold #ffd45a for biggest-fish/highlights
- Text: #f4f8fb; muted #9fb0bf; data in mono
- Display font: system (-apple-system / SF Pro Display), bold, tight tracking
- Body/mono: system + ui-monospace

## Storyboard (scene summary)
1. Hook — ~3.8s — faint satellite + "Most people just go fishing." → "We don't."
2. Replay — ~4.9s — replay.png fills frame; stat row ticks 17 FISH · 6.7 LB · 109 MILES · 21 HRS; "We logged every mile." (transition lands on strong cue 8.74)
3. Trip Wrapped — ~4.4s — wrapped.png rises with glow; "Then we gave it a Wrapped." (rise locked to 8.74; out on 13.11)
4. Ten ways — ~5.8s — title; 10 phones arrive one-by-one (card slides); converge on chip-board winner "the one we're building" (winner locked to strong cue 17.47)
5. Logo — ~3.3s — "FishingLogger" slam (locked to strong cue 19.66) + tagline; music tail.

## Audio
- Audio role: cinematic support — steady clean bed, one swell, light ticks, big bell moments
- Music: assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3 (volume 0.30, track 10)
- Music treatment: in by 0.4s; steady 0.30; soft duck under final logo (static low; render ends ~22s)
- Music cue guidance: bundled preset assets/music/happy-beats-...music-cues.json — tempo ~110 BPM.
  Strong cues: 8.74 (wrapped rise), 13.11 (into montage), 17.47 (winner converge), 19.66 (logo slam),
  22.93 (unused tail). Beat grid ~every 0.54s for phone arrivals.
- Audio-reactive treatment: UNAVAILABLE — hyperframes audio-reactive extraction helper not installed
  (scaffolded with --skip-skills). Approximated with a subtle CSS glow "breathe" on hero elements;
  not true per-frame audio reactivity. Documented per step-3 fallback.
- SFX (each own ascending track-index ≥ 11):
  - impactSoft_medium_001 @ ~0.5 (hook line)
  - drop_001 ticks on the 4 replay stats
  - impactBell_heavy_000 @ 8.74 (Wrapped rise)
  - casino/card-slide-1..4 rotating on the 10 phone arrivals (volume ~0.4)
  - impactSoft_medium_001 @ 17.47 (winner converge)
  - impactBell_heavy_003 @ 19.66 (logo slam)
- Restraint rule: music never above 0.4; let the bells ring; no busy SFX over holds.

## Hyperframes Instructions
- Single root timeline `window.__timelines["main"]`, paused; clips use class="clip" + data-start/
  data-duration/data-track-index; GSAP tweens at absolute times.
- Show real UI (all of it is). Keep text readable (cinematic floors). 15–25s total.
- Beat-lock the 3 biggest moments (8.74 Wrapped, 17.47 winner, 19.66 logo) within ±0.15s.
- Run `npm run check` and fix before render.
