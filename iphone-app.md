Yes. For your own iPhone, this weekend, the fastest path is:

Build a small iOS app in Xcode → run it directly on your iPhone → record GPS points locally → no App Store required.

Apple explicitly supports running apps on a physical device from Xcode; Xcode can register the device and create the development provisioning profile for you.   With a free Apple developer account, the catch is that the provisioning profile expires after 7 days, so you may need to rebuild/reinstall after that.  

What will work offline

Your iPhone can still get location without cell service. Core Location uses a combination of GPS, Wi-Fi, and cellular hardware, but GPS itself does not require an active data connection.  

What you can record offline:

Data	Works without cell?
Latitude / longitude	Yes
Timestamp	Yes
Accuracy estimate	Yes
Altitude	Usually
Speed / heading	Usually
Map tiles / satellite imagery	Not unless pre-downloaded
Uploading/syncing	No, until service returns

The cleanest weekend version is not a full mapping app. Make it a GPS logger that stores points locally as JSON or CSV.

Best path for this weekend

Use Xcode + SwiftUI + Core Location.

You do not need TestFlight or the App Store. TestFlight is useful for beta distribution, but it is extra ceremony for your own phone. Apple describes TestFlight as a beta-testing path before publishing, not the simplest route for one-device personal use.  

Setup steps

1. Install/open Xcode on your Mac.
2. Create a new iOS App project.
3. In Signing & Capabilities, choose your Apple account/team.
4. Use a unique bundle ID, like:

com.tylerhayes.OfflineGPSLogger

5. Add Location permission text in Info.plist:

<key>NSLocationWhenInUseUsageDescription</key>
<string>This app records my GPS location while I am using it.</string>

6. Connect your iPhone.
7. Select your iPhone as the run target.
8. Press Run.

For simple manual logging, use When In Use location permission. If you want continuous tracking while the phone is locked or the app is backgrounded, you need background location handling, and Apple requires clear “Always” location disclosure/permission behavior for background updates.  

Simple app design

For reliability, I’d build it with three buttons:

Start Tracking
Stop Tracking
Export CSV

Each point should store:

timestamp
latitude
longitude
horizontalAccuracy
altitude
speed
course

Then save locally to the app’s Documents directory as gps_log.csv.

Minimal Swift approach

The core logic would look roughly like this:

import Foundation
import CoreLocation
final class LocationLogger: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    @Published var isTracking = false
    private var points: [CLLocation] = []
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5 // meters
    }
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    func start() {
        points.removeAll()
        isTracking = true
        manager.startUpdatingLocation()
    }
    func stop() {
        isTracking = false
        manager.stopUpdatingLocation()
        saveCSV()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            guard location.horizontalAccuracy >= 0 else { continue }
            lastLocation = location
            points.append(location)
        }
    }
    private func saveCSV() {
        var csv = "timestamp,latitude,longitude,horizontal_accuracy,altitude,speed,course\n"
        for p in points {
            csv += "\(p.timestamp),\(p.coordinate.latitude),\(p.coordinate.longitude),\(p.horizontalAccuracy),\(p.altitude),\(p.speed),\(p.course)\n"
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gps_log.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        print("Saved to \(url)")
    }
}

For the UI, you’d wire that into a simple SwiftUI screen with Start/Stop buttons and display the latest lat/long.

Important limitations

The app can absolutely log GPS offline, but expect these realities:

Issue	Practical answer
First GPS fix may be slow	Open the app outside with clear sky before you need it
Battery drain	Continuous high-accuracy GPS can burn battery
No map imagery	Store coordinates only, or pre-download maps elsewhere
App expires with free account	Rebuild/install right before the weekend
Background tracking is harder	Manual foreground logging is much easier and more reliable

My recommendation

For this weekend, make version 1 dead simple:

1. Foreground app only.
2. Big “Log Point” button.
3. Optional “Start Continuous Logging” button.
4. Save CSV locally.
5. Export/share the CSV once you’re back online.

That avoids fighting iOS background behavior and gives you the thing you actually need: a timestamped trail of GPS points.

Q1: How would I build the full SwiftUI screen for this GPS logger?
Q2: How can I make the app export the CSV through the iPhone share sheet?
Q3: Can I make this record continuously while the phone is locked?