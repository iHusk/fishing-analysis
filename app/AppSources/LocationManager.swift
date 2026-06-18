//
//  LocationManager.swift
//  FishingLogger (iOS layer)
//
//  Core Location wrapper for the offline fishing logger. Drives the continuous
//  background "trail" track and feeds each good fix to `trackSink`.
//
//  Design notes (see docs/app-build-plan.md "Red-team revisions"):
//    - Background track logging on a metal boat with the phone in a pocket all
//      day. We keep WhenInUse location alive while locked by holding a
//      `CLBackgroundActivitySession` (iOS 17+), NOT by the accuracy constant.
//    - `allowsBackgroundLocationUpdates` is set INSIDE `startRecording()`, never
//      in `init`. Setting it without the "location" UIBackgroundMode in Info.plist
//      throws/crashes at runtime; deferring it means the app still launches and
//      logs catches even if the background mode is misconfigured.
//    - This manager is the COARSE/CONTINUOUS trail manager. The on-demand,
//      best-accuracy per-catch fix is a separate concern (Store/catch flow uses
//      the carried `current` fix or its own one-shot manager); mixing
//      `requestLocation()` into this live stream would silently no-op.
//
//  Pure-Foundation Core types live in FishingLoggerCore; this file is part of
//  the iOS app target only (imports CoreLocation / Combine).
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: Published state

    /// Last known good fix (horizontalAccuracy >= 0). nil until first fix.
    @Published var current: CLLocation?

    /// True once the user has granted WhenInUse (or Always) authorization.
    @Published var authorized: Bool = false

    /// True while a background trail recording session is active.
    @Published var isRecording: Bool = false

    // MARK: Sink

    /// Called on the main actor for each good fix while recording. The Store
    /// wires this to `appendTrackPoint(_:)` so every breadcrumb hits disk
    /// immediately in the delegate callback.
    var trackSink: ((CLLocation) -> Void)?

    // MARK: Private

    private let manager = CLLocationManager()

    /// Held only while recording. Typed `Any?` so the property exists on all
    /// deployment targets; the concrete `CLBackgroundActivitySession` (iOS 17+)
    /// is created/invalidated behind an availability guard.
    private var backgroundSession: Any?

    // MARK: Init

    override init() {
        super.init()
        manager.delegate = self

        // Trail config: coarse-but-steady continuous logging. HundredMeters is
        // visually identical to "best" on open water, sips battery, and (per
        // red-team) the accuracy constant does NOT govern background suspension.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .otherNavigation
        manager.showsBackgroundLocationIndicator = true

        // Reflect whatever authorization the system already has at launch.
        syncAuthorized(manager.authorizationStatus)
    }

    // MARK: Authorization & start

    /// Request WhenInUse authorization. (We rely on the background activity
    /// session, not "Always", to keep WhenInUse logging alive while locked.)
    func requestAuth() {
        manager.requestWhenInUseAuthorization()
    }

    /// Begin the standard (foreground-capable) location stream so `current`
    /// stays warm for catch tagging even when not recording a trail.
    func start() {
        manager.startUpdatingLocation()
    }

    // MARK: Recording (background trail)

    /// Start the all-day background trail. Safe to call repeatedly.
    func startRecording() {
        guard !isRecording else { return }

        // Set background updates HERE, guarded. If the "location" background
        // mode is missing from Info.plist this assignment can trap; tolerate it
        // so the app keeps running (foreground logging still works).
        if manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse {
            enableBackgroundUpdatesIfPossible()
        }

        // Hold a background activity session (iOS 17+). THIS is what keeps a
        // WhenInUse app logging location while the screen is locked.
        if #available(iOS 17.0, *) {
            backgroundSession = CLBackgroundActivitySession()
        }

        isRecording = true
        manager.startUpdatingLocation()
    }

    /// Stop the background trail. Leaves the foreground stream (`start()`)
    /// running so `current` stays available for catch tagging.
    func stopRecording() {
        guard isRecording else { return }

        if #available(iOS 17.0, *) {
            (backgroundSession as? CLBackgroundActivitySession)?.invalidate()
        }
        backgroundSession = nil

        manager.allowsBackgroundLocationUpdates = false
        isRecording = false
        // Keep `startUpdatingLocation` running for warm catch fixes; the app
        // shell starts it on launch and we don't tear it down here.
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        // Hop to the main actor: we touch @Published state and the sink.
        Task { @MainActor in
            // Last good fix wins. Reject the invalid-accuracy sentinel (< 0).
            guard let fix = locations.last(where: { $0.horizontalAccuracy >= 0 }) else {
                return
            }
            self.current = fix

            if self.isRecording {
                // Forward every good fix while recording (delegate may batch
                // several). Write-to-disk happens in the sink immediately.
                for loc in locations where loc.horizontalAccuracy >= 0 {
                    self.trackSink?(loc)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Transient failures (e.g. brief loss of lock offline) are expected and
        // recoverable; Core Location keeps trying. Nothing to tear down here.
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.syncAuthorized(status)
            // If the user grants access after we've already started recording,
            // promote to background updates now.
            if self.isRecording,
               status == .authorizedAlways || status == .authorizedWhenInUse {
                self.enableBackgroundUpdatesIfPossible()
            }
        }
    }

    // MARK: Helpers

    private func syncAuthorized(_ status: CLAuthorizationStatus) {
        authorized = (status == .authorizedAlways || status == .authorizedWhenInUse)
    }

    /// Turn on background updates, tolerating a missing "location" background
    /// mode (which would otherwise trap). Never let configuration crash the app.
    private func enableBackgroundUpdatesIfPossible() {
        guard !manager.allowsBackgroundLocationUpdates else { return }
        manager.allowsBackgroundLocationUpdates = true
    }
}
