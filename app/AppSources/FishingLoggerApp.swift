import SwiftUI

/// App shell for FishingLogger.
///
/// Wires together the two long-lived observable objects the whole UI depends on:
///   - `Store`            — the airtight, on-disk source of truth (catches.json /
///                          weights.json + the always-current CSV mirrors + track.csv).
///   - `LocationManager`  — Core Location plumbing for the live GPS fix and the
///                          background travel track.
///
/// Both are created here as `@StateObject` so they live exactly as long as the app
/// process and are never re-instantiated on a view redraw. They are injected into
/// the view tree via `.environmentObject(...)`, which is the contract the views in
/// AppSources/ rely on (`@EnvironmentObject var store: Store`, etc.).
@main
struct FishingLoggerApp: App {
    @StateObject private var store = Store()
    @StateObject private var loc = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(loc)
                .onAppear {
                    // The track sink is the bridge from Core Location to disk: every
                    // good fix the LocationManager produces while recording is handed
                    // to the Store, which appends one line to track.csv. Keeping this
                    // wiring here (not inside either object) avoids a retain cycle
                    // between them and keeps each object independently testable.
                    loc.trackSink = { [weak store] fix in
                        store?.appendTrackPoint(fix)
                    }

                    // Ask for location permission and start the (coarse, low-cost)
                    // standard updates so `current` is populated and ready to tag a
                    // catch the moment the user opens the Log Catch sheet. The
                    // higher-cost background travel track is started explicitly by
                    // the user from ContentView (Start/Stop Track), not here.
                    loc.requestAuth()
                    loc.start()
                }
        }
    }
}
