import SwiftUI
import os

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
    @StateObject private var profiles = AnglerProfileStore()

    /// Launch-timing channel. Mirrors Store.swift so the whole boot story shows up
    /// under one subsystem in Console / Instruments (subsystem "FishingLogger",
    /// category "launch").
    private static let launchLog = Logger(subsystem: "FishingLogger", category: "launch")
    /// Process start, captured once so first-appear can be reported relative to it.
    private static let processStart = CFAbsoluteTimeGetCurrent()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(loc)
                .environmentObject(profiles)
                .onAppear {
                    // First-appear marker: how long from process start until the root
                    // view is on screen and interactive. Logged to the Xcode console so
                    // the owner can read total perceived launch latency at a glance.
                    let ms = (CFAbsoluteTimeGetCurrent() - Self.processStart) * 1000
                    Self.launchLog.log("launch: ContentView first-appear at \(ms, format: .fixed(precision: 1)) ms from process start")

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
