# FishingLogger iOS app — build, sideload & Xcode-MCP workflow

How the offline iPhone catch/track logger is developed, kept in sync, built, and put on the
phone — and how we drive Xcode from this session via the **xcode MCP**.

---

## 1. What the app is
**FishingLogger** — a native **SwiftUI + Core Location** iOS app (iOS 17+) that logs walleye
catches and the boat's GPS track on Lake Oahe, **fully offline** (no cell service needed for
GPS/logging — only map tiles and syncing need a network). It's sideloaded with a **free Apple
ID**, used ~a week a year. It exports the CSVs this repo's analysis + replay map consume.

Why these choices (see also `docs/app-build-plan.md`):
- **Free Apple ID** sideload → 7-day provisioning profile. **Rebuild before each trip; do NOT
  delete the app** (its sandbox holds the data). $99/yr paid account is the fallback if signing
  becomes a problem mid-trip (can re-sign same evening).
- **Two `CLLocationManager`s**: a continuous coarse trail + an on-demand precise fix at a catch.
- **`CLBackgroundActivitySession`** (iOS 17+) for background tracking — backgrounding the app
  keeps tracking; **force-quitting kills it** (expected; tell the user not to swipe it closed).
- **File protection** `.completeFileProtectionUntilFirstUserAuthentication` so writes succeed
  while the phone is locked in a pocket (the iOS-default `NSFileProtectionComplete` silently
  fails when locked).
- **Airtight persistence**: JSON source-of-truth + CSV mirror, **atomic writes**
  (`Data.WritingOptions [.atomic, .completeFileProtectionUntilFirstUserAuthentication]`),
  `track.csv` appended via `FileHandle`.

---

## 2. Where the code lives (TWO locations, synced by hand)
1. **Canonical source + tests + docs — THIS repo, under `app/`:**
   - `app/FishingLoggerCore/` — pure-Foundation logic (no UIKit): models, CSV `Schema`,
     `DateFmt`, JSON `CatchStore`/`WeightStore`. Has **27 XCTest** unit tests. Run them with:
     ```
     DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
     ```
   - `app/AppSources/` — the SwiftUI layer (views, `Store`, `LocationManager`, …).
   - `app/README-XCODE-SETUP.md` — first-time sideload guide.
2. **The runnable Xcode project — a SEPARATE PRIVATE repo `iHusk/FishingLogger`:**
   - On disk at `~/Documents/xcode-projects/FishingLogger`.
   - Uses an **Xcode synchronized folder group** (`PBXFileSystemSynchronizedRootGroup`): the
     Core `.swift` files are **COPIED in and compiled directly** — there is **no
     `import FishingLoggerCore`**, no SwiftPM link. (Single module; the package split is only
     for running unit tests here.)

**Sync workflow:** edit in `app/AppSources` here → `cp` the changed files into the Xcode
project's source folder → build via the xcode MCP. Keep the locked CSV schema identical on both
sides (see `docs/app-build-plan.md` → "Final data schema").

---

## 3. Driving Xcode from this session — the **xcode MCP**
The xcode MCP lets the agent build, inspect issues, read the build log, and edit files inside
the open Xcode project without the user copy-pasting. Tools used (names as exposed by the MCP):
- `mcp__xcode__XcodeListWindows` — find the open project window/tab. The FishingLogger project
  has historically been tab **`windowtab2`**; re-list if it moved.
- `mcp__xcode__BuildProject` — build the project (target the FishingLogger tab).
- `mcp__xcode__XcodeListNavigatorIssues` / `mcp__xcode__GetBuildLog` — read compiler errors /
  the raw build log to diagnose failures.
- File ops: `XcodeRead`, `XcodeWrite`, `XcodeUpdate`, `XcodeGlob`, `XcodeGrep`, `XcodeLS`,
  `XcodeMV`, `XcodeRM`, `XcodeMakeDir`, `XcodeGetCurrentFile`, `XcodeRefreshCodeIssuesInFile`.
- Tests/preview: `RunAllTests`, `RunSomeTests`, `GetTestList`, `RenderPreview`,
  `DocumentationSearch`, `ExecuteSnippet`.

These are **deferred** tools — fetch the schema with `ToolSearch` (e.g.
`select:mcp__xcode__BuildProject`) before the first call.

Typical loop: edit `app/AppSources/X.swift` → `cp` to the Xcode project → `BuildProject` →
if it fails, `XcodeListNavigatorIssues` / `GetBuildLog` → fix → rebuild.

---

## 4. First-time sideload checklist (free Apple ID)
Full walkthrough in `app/README-XCODE-SETUP.md`. The non-obvious bits that bit us:
- **Synchronized folder group**: just drop the `.swift` files into the project's source folder
  on disk; Xcode auto-adds them to the target. Keep the folder structure.
- **Signing**: Xcode → target → Signing & Capabilities → Team = your *Personal Team* (free).
  "Communication with Apple failed / no devices" + "No profiles found" is **normal until a
  device is connected** — plug in the iPhone and it resolves.
- **Info keys** are generated from `INFOPLIST_KEY_*` build settings + an optional physical
  `Info.plist` (`INFOPLIST_FILE`) that merge. Use the friendly autocomplete names (e.g.
  `NSLocationWhenInUseUsageDescription`, capital `NS`).
- **Background tracking**: add `UIBackgroundModes = [location]` directly to the physical
  `Info.plist` (the Background Modes capability UI was confusing and wrote nothing). Also set
  `UIFileSharingEnabled = true` so exports are reachable.
  Project `Info.plist`: `~/Documents/xcode-projects/FishingLogger/FishingLogger/Info.plist`.
- **Device**: enable **Developer Mode** on the iPhone (Settings → Privacy & Security). "The
  developer disk image could not be mounted" → unlock the phone / Window → Devices & Simulators
  is preparing / reconnect. Note the phone may be on a *different* Apple account than the Mac —
  that's fine for a free Personal Team.
- **Testing System** when creating the project: choose **None** (we run logic tests via the
  Swift package here, not Xcode's test bundle).

**Before every trip:** rebuild & reinstall (refreshes the 7-day profile); same bundle ID
preserves the sandbox data. **On the water:** Start Track at the dock, don't swipe the app
closed, jot the bag weight on paper as backup.

---

## 5. Export → analysis handoff
The app exports three CSVs on the **locked schema** (`catches.csv`, `track.csv`,
`daily_weights.csv`) plus JSON source-of-truth. They feed:
- the **replay map** (`replay_trip.py`, see `docs/replay-map-spec.md`), and
- (post-trip) the historical analysis (`load_data()` rewrite is pending — see README).

**AirDrop rename gotcha:** files often arrive named `catches 3.csv` / `track 3.csv` (Finder
de-dupe). The tools need the canonical `catches.csv` / `track.csv` — copy/rename first.
**The export accumulates:** each day's export is a *superset* of all prior days (the app keeps
history), so the latest folder is the whole trip; do NOT `--all` across the dated folders (they
overlap and would double-count).

See [[fishing-logger-app]] memory note for the live pointer.
