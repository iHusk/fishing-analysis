# FishingLogger — Xcode setup (first-time, foolproof)

This guide turns the Swift source in this folder into a running app on **your own
iPhone**, with **no Apple Developer Program payment** (free Apple ID). It assumes you
have **never used Xcode before**. Follow the numbered steps in order; do not skip.

You need:

- A **Mac** (the laptop you bring on the trip is fine).
- An **iPhone running iOS 17 or newer**, plus its **USB cable**.
- An **Apple ID** (the same one you use on the iPhone is easiest).
- ~1 hour the first time. Once it works, a rebuild later takes ~5 minutes.

Where the code lives:

```
/Users/thayes-mac/Documents/GitHub/fishing-analysis/app/
  FishingLoggerCore/Sources/FishingLoggerCore/   <- pure-Foundation models + CSV (the 4 .swift files)
  AppSources/                                      <- SwiftUI + Core Location app layer
  AppSources/Info-plist-additions.txt              <- the 5 Info keys (Step 7)
```

---

## 1. Install Xcode

1. Open the **App Store** on the Mac.
2. Search **Xcode**, click **Get / Install** (it is large, ~7–15 GB — do this on
   Wi‑Fi, not the morning of the trip).
3. After it installs, **open Xcode once**. Accept the license. If it asks to install
   "additional required components," let it. Wait until it finishes.

---

## 2. Create the app project

1. In Xcode: **File > New > Project…** (or on the welcome screen, **Create New
   Project…**).
2. At the top choose the **iOS** tab. Pick the **App** template. Click **Next**.
3. Fill the form **exactly** like this:
   - **Product Name:** `FishingLogger`  (no spaces — must be this so the
     `@main struct FishingLoggerApp` matches)
   - **Team:** leave for now (Step 8 handles signing) — or pick your name if it's
     already listed.
   - **Organization Identifier:** `com.tylerhayes`
   - **Bundle Identifier:** Xcode shows this auto-filled as
     **`com.tylerhayes.fishinglogger`** — confirm it reads exactly that. This is the
     app's permanent identity. **Keep it stable forever**: reinstalling the SAME
     bundle id preserves all logged data; changing it makes iOS treat it as a brand
     new app with an empty data folder.
   - **Interface:** **SwiftUI**
   - **Language:** **Swift**
   - **Testing System:** **None** (the data-core tests live in the separate
     `FishingLoggerCore` Swift package; the app target needs no test target).
   - **Storage:** **None** — ⚠️ newer Xcode **defaults this to "Core Data"**; you must
     change it to **None**. The app uses its own flat-file storage; Core Data would add
     boilerplate we don't want.
   - **Host in CloudKit:** **unchecked**.
4. Click **Next**. Choose a folder to save the project (anywhere outside this repo is
   fine, e.g. your Desktop). Click **Create**.

You now have a project with some template files. We replace them next.

---

## 3. Set the minimum iOS version to 17

1. In the left **Project navigator**, click the **blue project icon** at the very top
   (named `FishingLogger`).
2. In the main pane, under **TARGETS**, select **FishingLogger**.
3. Open the **General** tab.
4. Find **Minimum Deployments** (or "Deployment Info"). Set **iOS** to **17.0**.

---

## 4. Delete the two auto-generated template files

Xcode created two starter files we do **not** want (our code replaces them):

- `FishingLoggerApp.swift`  (the template app shell)
- `ContentView.swift`       (the template view)

1. In the Project navigator, **select both** of those files (click one, ⌘-click the
   other).
2. Press **Delete** (or right-click > **Delete**).
3. In the popup, choose **Move to Trash** (not "Remove Reference"). They must be gone
   so they don't collide with the real `FishingLoggerApp.swift` / `ContentView.swift`
   we add in Step 5.

> If you skip this you'll get errors like "invalid redeclaration of 'ContentView'"
> or "'main' attribute can only apply to one type." That just means a template twin
> is still there — delete it.

---

## 5. Add ALL the real source files

You will drag in **every `.swift` file** from **two folders**:

- `/Users/thayes-mac/Documents/GitHub/fishing-analysis/app/FishingLoggerCore/Sources/FishingLoggerCore/`
  (the Core models / CSV / date / JSON — `Models.swift`, `Schema.swift`,
  `DateFmt.swift`, `Stores.swift`)
- `/Users/thayes-mac/Documents/GitHub/fishing-analysis/app/AppSources/`
  (the app layer — `FishingLoggerApp.swift`, `Store.swift`, `LocationManager.swift`,
  `ContentView.swift`, and the other view files)

Steps:

1. Open **Finder** and navigate to the first folder above
   (`FishingLoggerCore/Sources/FishingLoggerCore/`).
2. Select **all the `.swift` files** in it (⌘-A selects everything; that folder
   contains only the four `.swift` files).
3. **Drag them onto the `FishingLogger` group** (the yellow folder) in Xcode's left
   Project navigator.
4. In the dialog that appears:
   - **Check** ✅ **"Copy items if needed"**.
   - Under **"Add to targets"**, **check** ✅ **FishingLogger**.
   - Click **Finish**.
5. Repeat 1–4 for the **AppSources** folder
   (`/Users/thayes-mac/Documents/GitHub/fishing-analysis/app/AppSources/`). Select
   only the **`.swift`** files there. **Do NOT add** `Info-plist-additions.txt` or
   `README-XCODE-SETUP.md` — those are not source code.

> IMPORTANT — do **not** add the test files. The folder
> `FishingLoggerCore/Tests/FishingLoggerCoreTests/` is for the Core package's own
> tests on macOS; those files must **not** be added to the iPhone app target. Only
> add files from the two folders named above.

After this, the Project navigator should list (among others):
`FishingLoggerApp.swift`, `ContentView.swift`, `Store.swift`,
`LocationManager.swift`, the other views, plus `Models.swift`, `Schema.swift`,
`DateFmt.swift`, `Stores.swift`.

> Note: in the app target we compile the Core `.swift` files **directly** alongside
> the app code, so there is **no `import FishingLoggerCore`** and **no Swift package
> to link** — that's why Step 5 drags in the Core sources themselves. (The
> `Package.swift` in `FishingLoggerCore/` exists only to build & unit-test the Core
> on the Mac from the command line; see the appendix at the bottom.)

---

## 6. (Sanity check) Build for the Simulator

1. At the top of the Xcode window, next to the Run ▶︎ button, click the device
   menu and pick any **iPhone … (simulator)**, e.g. "iPhone 15".
2. Press **⌘B** (Product > Build).
3. It should say **Build Succeeded**. If you get errors, the most common cause is a
   leftover template file from Step 4 — go delete it. (Location features won't do
   anything useful in the simulator; that's expected. We build on the real phone in
   Step 9.)

---

## 7. Add the 5 Info.plist keys

Open `/Users/thayes-mac/Documents/GitHub/fishing-analysis/app/AppSources/Info-plist-additions.txt`
and follow it. In short:

1. Project navigator > **blue project icon** > **TARGETS > FishingLogger** > **Info**
   tab > **Custom iOS Target Properties**.
2. Use the **"+"** on any row to add these four, with the values from the txt file:
   - `NSLocationWhenInUseUsageDescription` (String)
   - `NSLocationAlwaysAndWhenInUseUsageDescription` (String)
   - `UIFileSharingEnabled` (Boolean = YES)
   - `LSSupportsOpeningDocumentsInPlace` (Boolean = YES)
3. The **fifth** (Background Modes / `location`) is added in Step 8 via a capability —
   don't hand-type it.

---

## 8. Signing + the Background Modes capability

1. Project navigator > **blue project icon** > **TARGETS > FishingLogger** >
   **Signing & Capabilities** tab.
2. **Signing:**
   - Check ✅ **Automatically manage signing**.
   - **Team:** click the dropdown > **Add an Account…** > sign in with your **Apple
     ID** > close that window. Back in the dropdown, pick your name — it will read
     something like **"Tyler Hayes (Personal Team)"**. (This is the free path; no
     payment.)
   - If you see a red error about the bundle id being unavailable, just tweak the
     **Bundle Identifier** slightly (e.g. `com.tylerhayes.fishinglogger1`) and then
     **keep it stable from then on**.
3. **Capability — Background Modes:**
   - Click **"+ Capability"** (top-left of this tab).
   - Double-click **Background Modes**.
   - In the list that appears, **tick "Location updates"**. (This writes the
     `UIBackgroundModes = [location]` key for you — that's key #5 from the txt file.)

---

## 9. Run it on your iPhone

1. **Plug the iPhone into the Mac** with the USB cable. If the phone asks **"Trust
   This Computer?"**, tap **Trust** and enter the passcode.
2. **Enable Developer Mode on the iPhone** (required on iOS 16+):
   - On the **iPhone**: **Settings > Privacy & Security > Developer Mode > On**. The
     phone will prompt to **restart**; let it, then unlock and confirm. (If you don't
     see "Developer Mode," first do step 3 below once — connecting to Xcode makes the
     toggle appear, then come back here.)
3. **In Xcode**, click the device menu (top, next to ▶︎) and select **your iPhone by
   name** (under "iOS Device"), not a simulator.
4. Press **Run ▶︎** (⌘R). Xcode builds and installs to the phone.
5. **First launch will be blocked** with "Untrusted Developer." On the **iPhone**:
   **Settings > General > VPN & Device Management** > tap your developer Apple ID >
   **Trust** > confirm. (See the Pre-trip checklist in `docs/app-build-plan.md` — do
   this **while in cell/Wi-Fi service**.)
6. Back on the phone, tap the **FishingLogger** icon. It should open to the main
   screen. Grant **Location** permission when asked — choose **Allow While Using**,
   then later **Change to Always** in Settings for the all-day background track.

---

## 10. Verify the round-trip (do this before the trip, in service)

1. In the app, tap **LOG CATCH**, save a test fish. Confirm the **counter increments**
   and you see a save confirmation.
2. **Force-quit** the app (swipe it away in the app switcher) and **reopen** it — the
   test catch must **still be there**. (This proves the write hit disk, the whole
   point of "airtight.")
3. Tap **Export** and AirDrop/email the CSVs to yourself. Open `catches.csv` and
   confirm your test row is present with the locked header
   (`id,uuid,timestamp_local,…,notes`).
4. Open the **Files** app > **On My iPhone > FishingLogger** — you should see
   `catches.csv`, `daily_weights.csv`, and (after you Start Track) `track.csv`. This
   is your break-glass copy if the app ever won't launch.
5. **Delete the test catch** from the Day Log so it doesn't pollute real data.

---

## 11. Now follow the Pre-trip checklist

Before you leave for Lake Oahe, run the **"Pre-trip checklist (free profile — do in
order, WHILE IN SERVICE)"** in
`/Users/thayes-mac/Documents/GitHub/fishing-analysis/docs/app-build-plan.md`. The key
points:

- **Build & install the morning of departure** — the free signing profile **expires
  after ~7 days**, after which the app won't launch until you rebuild from the Mac.
  Reinstalling the **same bundle id does NOT erase data**, so a mid-trip rebuild is
  safe. **Bring the MacBook + cable** as the break-glass rebuild.
- **Trust the cert online** and **launch the app to its main screen with no prompts
  while still in service** (caches the trust so a lakeside reboot won't block you).
- **Location: Always + Precise.** Turn **off Low Power Mode** (it throttles background
  location). Keep the phone on a **power bank** all day.
- **Export every evening** when you're back in service — that off-device CSV is the
  **only real backup** (iCloud backup does **not** restore a sideloaded app's data).
- Bring **paper for the daily bag weight** — the one number that can't be re-derived.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Invalid redeclaration of 'ContentView'" / "'main' can only apply to one type" | A template twin from Step 4 still exists — delete `FishingLoggerApp.swift` / `ContentView.swift` that Xcode auto-created. |
| "Cannot find 'FishCatch' (or 'Store', 'Schema', …) in scope" | A source file didn't get added to the target. Re-do Step 5; make sure **"Add to targets: FishingLogger"** was checked. |
| App crashes the instant you press **Start Track** | The Background Modes > **Location updates** capability is missing — redo Step 8.3. |
| "Untrusted Developer" won't go away | Settings > General > VPN & Device Management > Trust your Apple ID (Step 9.5), while in service. |
| App won't launch after a few days on the trip | Free profile expired (~7 days). Rebuild from the MacBook (⌘R) — **data is preserved**. |
| Writes seem to stop while phone is locked in pocket | The app writes with `.completeFileProtectionUntilFirstUserAuthentication` to avoid exactly this; if you see it, confirm you unlocked the phone at least once since the last reboot. |

---

## Appendix — building & testing FishingLoggerCore from the command line (Mac only)

The Core library is also a standalone SwiftPM package (`app/FishingLoggerCore`) with
its own XCTest suite. This is **not needed to build the app** — it's how the
pure-Foundation core is verified on the Mac. XCTest ships only with the full Xcode
app (not the standalone Command Line Tools), so point `swift` at the Xcode toolchain:

```sh
cd /Users/thayes-mac/Documents/GitHub/fishing-analysis/app/FishingLoggerCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

(Equivalent: run `sudo xcode-select -s /Applications/Xcode.app` once, then plain
`swift build` / `swift test`.) No third-party dependencies; platforms macOS .v13,
iOS .v17.
