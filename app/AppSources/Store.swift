import Foundation
import Combine
import CoreLocation
import os

/// Lightweight launch-timing channel. View it in Console.app / the Xcode console
/// (subsystem "FishingLogger", category "launch") and as signpost intervals in
/// Instruments (os_signpost / Time Profiler), e.g. the "Store.load" interval.
private let launchLog = Logger(subsystem: "FishingLogger", category: "launch")
private let launchSignpost = OSSignposter(subsystem: "FishingLogger", category: "launch")

/// The app's single source of truth for catches and weigh sessions.
///
/// Durability model (matches the LOCKED build plan):
///   - JSON files (`catches.json` / `weights.json`) are the source of truth.
///   - On every mutation we also rewrite the CSV mirrors (`catches.csv` /
///     `daily_weights.csv`) via `Schema`, so an always-current, Files-app-visible,
///     pipeline-ready export exists even if the app later won't launch.
///   - `track.csv` is append-only: created with its header once, then a line is
///     appended per good GPS fix.
///   - ALL writes use `.atomic` + `.completeFileProtectionUntilFirstUserAuthentication`
///     so writes succeed while the phone is locked in a pocket all day, and a partial
///     write can never corrupt an existing file.
///
/// "Saved" means the write call returned — the confirmation *is* the committed write.
@MainActor
final class Store: ObservableObject {

    // MARK: - Published state

    @Published var catches: [FishCatch] = []
    @Published var weights: [DailyWeight] = []

    /// Active weigh session = the fishing-day key the catch/bag are stamped with.
    @Published var activeSessionID: String
    /// Active trip marker (e.g. "2026-06").
    @Published var activeTrip: String

    // Carry-forward fields (last value used, prefilled on the next catch).
    @Published var lastFisherman: String = ""
    @Published var lastLength: Double = 15.0
    @Published var lastDepth: Double = 20.0
    @Published var lastWaterTemp: Double? = nil
    @Published var lastLure1: String = ""
    @Published var lastLure2: String = ""
    @Published var lastBait: String = ""
    @Published var lastLocationName: String = ""
    @Published var knownFishermen: [String] = []

    /// Dropdown option lists: defaults + anything seen in saved catches + custom adds.
    @Published var knownSpecies: [String] = Store.defaultSpecies
    @Published var knownLureColors: [String] = Store.defaultLureColors

    /// Sensible starting lists (Lake Oahe species + common walleye colors).
    static let defaultSpecies = ["walleye", "sauger", "perch", "northern pike",
                                 "smallmouth bass", "white bass", "crappie",
                                 "catfish", "chinook salmon"]
    static let defaultLureColors = ["Bare", "Red Hooks", "Chartreuse", "Firetiger",
                                    "Gold", "Silver", "Purple", "Pink", "White",
                                    "Orange", "Glow", "Black", "Blue", "Green",
                                    "Perch", "Clown"]

    // MARK: - File locations

    private let docs: URL
    private let catchesJSONURL: URL
    private let weightsJSONURL: URL
    private let catchesCSVURL: URL
    private let weightsCSVURL: URL
    private let trackCSVURL: URL

    /// Atomic + file-protection write options used for every file write.
    private let writeOptions: Data.WritingOptions =
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    // MARK: - Init

    init() {
        let t0 = CFAbsoluteTimeGetCurrent()
        let initState = launchSignpost.beginInterval("Store.init")
        defer {
            launchSignpost.endInterval("Store.init", initState)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            launchLog.log("launch: Store.init took \(ms, format: .fixed(precision: 1)) ms")
        }

        let fm = FileManager.default
        // Documents is sandboxed and Files-app-visible (UIFileSharingEnabled).
        self.docs = (try? fm.url(for: .documentDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: nil,
                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        self.catchesJSONURL = docs.appendingPathComponent("catches.json")
        self.weightsJSONURL = docs.appendingPathComponent("weights.json")
        self.catchesCSVURL  = docs.appendingPathComponent("catches.csv")
        self.weightsCSVURL  = docs.appendingPathComponent("daily_weights.csv")
        self.trackCSVURL    = docs.appendingPathComponent("track.csv")

        let now = Date()
        self.activeSessionID = DateFmt.dayKey(now)   // yyyy-MM-dd local
        self.activeTrip = DateFmt.tripKey(now)       // yyyy-MM local

        load()
    }

    // MARK: - Loading

    /// Load the JSON source-of-truth files (if present) and rebuild carry-forward.
    ///
    /// Instrumented for launch profiling: a "Store.load" signpost interval (visible
    /// in Instruments / Time Profiler) wraps the whole step, and per-phase elapsed-ms
    /// lines are logged to the Xcode console so the read+decode vs. rebuild split is
    /// readable without attaching Instruments.
    private func load() {
        let loadState = launchSignpost.beginInterval("Store.load")
        let t0 = CFAbsoluteTimeGetCurrent()

        if let data = try? Data(contentsOf: catchesJSONURL),
           let rows = try? CatchStore.decode(data) {
            catches = rows
        }
        if let data = try? Data(contentsOf: weightsJSONURL),
           let rows = try? WeightStore.decode(data) {
            weights = rows
        }
        let tDecoded = CFAbsoluteTimeGetCurrent()

        rebuildCarryForward()
        let tDone = CFAbsoluteTimeGetCurrent()

        launchSignpost.endInterval("Store.load", loadState)
        let readMs = (tDecoded - t0) * 1000
        let rebuildMs = (tDone - tDecoded) * 1000
        let totalMs = (tDone - t0) * 1000
        launchLog.log("launch: Store.load took \(totalMs, format: .fixed(precision: 1)) ms (read+decode \(readMs, format: .fixed(precision: 1)) ms, rebuildCarryForward \(rebuildMs, format: .fixed(precision: 1)) ms, \(self.catches.count) catches, \(self.weights.count) weights)")
    }

    /// Restore carry-forward defaults + known-fishermen list from the most recent catch.
    private func rebuildCarryForward() {
        // Single pass over `catches`: build the de-duplicated known-fishermen list
        // (stable, first-seen order) AND fold any species / lure colors into the
        // option lists at the same time. Both were previously separate loops over the
        // same array; merging halves the launch-time iteration. Results are identical:
        // the fishermen de-dupe order is unchanged, and noteSpecies/noteLureColor are
        // order-independent and idempotent.
        var seen = Set<String>()
        var names: [String] = []
        for c in catches {
            let name = c.fisherman.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !seen.contains(name) {
                seen.insert(name)
                names.append(name)
            }
            noteSpecies(c.species)
            noteLureColor(c.lureColor1)
            noteLureColor(c.lureColor2)
        }
        knownFishermen = names

        // Carry-forward from the newest catch by timestamp.
        if let last = catches.max(by: { $0.timestamp < $1.timestamp }) {
            lastFisherman = last.fisherman
            lastLength = last.lengthIn
            lastDepth = last.depthFt
            lastWaterTemp = last.waterTempF
            lastLure1 = last.lureColor1
            lastLure2 = last.lureColor2
            lastBait = last.bait
            lastLocationName = last.locationName
        }
    }

    // MARK: - Catch mutations

    @discardableResult
    func addCatch(
        fisherman: String,
        species: String,
        kept: Bool,
        lengthIn: Double,
        depthFt: Double,
        waterTempF: Double?,
        lure1: String,
        lure2: String,
        bait: String,
        locationName: String,
        measuredWtLbs: Double? = nil,
        loc: CLLocation?
    ) -> FishCatch {
        let newID = (catches.map { $0.id }.max() ?? 0) + 1
        let now = Date()

        // Only accept a usable GPS fix.
        let lat: Double?
        let lon: Double?
        let acc: Double?
        let heading: Double?
        if let loc = loc, loc.horizontalAccuracy >= 0 {
            lat = loc.coordinate.latitude
            lon = loc.coordinate.longitude
            acc = loc.horizontalAccuracy
            heading = loc.course >= 0 ? loc.course : nil
        } else {
            lat = nil; lon = nil; acc = nil; heading = nil
        }

        let newCatch = FishCatch(
            id: newID,
            uuid: UUID().uuidString,
            timestamp: now,
            weighSessionID: activeSessionID,
            trip: activeTrip,
            fisherman: fisherman,
            species: species,
            kept: kept,
            lengthIn: lengthIn,
            depthFt: depthFt,
            waterTempF: waterTempF,
            lureColor1: lure1,
            lureColor2: lure2,
            bait: bait,
            locationName: locationName,
            lat: lat,
            lon: lon,
            gpsAccuracyM: acc,
            headingDeg: heading,
            notes: "",
            measuredWtLbs: measuredWtLbs
        )

        catches.append(newCatch)

        // Update carry-forward.
        lastFisherman = fisherman
        lastLength = lengthIn
        lastDepth = depthFt
        lastWaterTemp = waterTempF
        lastLure1 = lure1
        lastLure2 = lure2
        lastBait = bait
        lastLocationName = locationName
        let trimmed = fisherman.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !knownFishermen.contains(trimmed) {
            knownFishermen.append(trimmed)
        }
        noteSpecies(species)
        noteLureColor(lure1)
        noteLureColor(lure2)

        persistCatches()
        return newCatch
    }

    func updateCatch(_ updated: FishCatch) {
        guard let idx = catches.firstIndex(where: { $0.uuid == updated.uuid }) else { return }
        catches[idx] = updated
        rebuildCarryForward()
        persistCatches()
    }

    func deleteCatch(_ target: FishCatch) {
        catches.removeAll { $0.uuid == target.uuid }
        persistCatches()
    }

    // MARK: - Weigh-in mutations

    /// Upsert a weigh session by its `weighSessionID`.
    func saveWeight(_ weight: DailyWeight) {
        if let idx = weights.firstIndex(where: { $0.weighSessionID == weight.weighSessionID }) {
            weights[idx] = weight
        } else {
            weights.append(weight)
        }
        persistWeights()
    }

    // MARK: - Derived

    /// Today's catches: those in the active session, newest first.
    var todaysCatches: [FishCatch] {
        catches
            .filter { $0.weighSessionID == activeSessionID }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Count of catches per weigh session — feeds `n_catches_logged` in the CSV.
    private var catchCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for c in catches { counts[c.weighSessionID, default: 0] += 1 }
        return counts
    }

    // MARK: - Persistence

    /// Rewrite catches.json (source of truth) then catches.csv (mirror), atomically.
    private func persistCatches() {
        if let data = try? CatchStore.encode(catches) {
            try? data.write(to: catchesJSONURL, options: writeOptions)
        }
        let csv = Schema.catchesCSV(catches)
        if let data = csv.data(using: .utf8) {
            try? data.write(to: catchesCSVURL, options: writeOptions)
        }
    }

    /// Rewrite weights.json (source of truth) then daily_weights.csv (mirror), atomically.
    private func persistWeights() {
        if let data = try? WeightStore.encode(weights) {
            try? data.write(to: weightsJSONURL, options: writeOptions)
        }
        let csv = Schema.weightsCSV(weights, catchCounts: catchCounts)
        if let data = csv.data(using: .utf8) {
            try? data.write(to: weightsCSVURL, options: writeOptions)
        }
    }

    // MARK: - Track (append-only)

    /// Append one GPS fix to track.csv. Creates the file with its header (and file
    /// protection) on first use, then appends a single line per good fix.
    func appendTrackPoint(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0 else { return }

        let point = TrackPoint(
            timestamp: loc.timestamp,
            trip: activeTrip,
            weighSessionID: activeSessionID,
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            accuracyM: loc.horizontalAccuracy,
            altitudeM: loc.altitude,
            speedMps: loc.speed >= 0 ? loc.speed : nil,
            courseDeg: loc.course >= 0 ? loc.course : nil
        )

        ensureTrackFileExists()

        let line = Schema.trackLine(point) + "\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: trackCSVURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    /// Create track.csv with its header and full file protection if it does not exist yet.
    private func ensureTrackFileExists() {
        guard !FileManager.default.fileExists(atPath: trackCSVURL.path) else { return }
        let header = Schema.trackHeader + "\n"
        if let data = header.data(using: .utf8) {
            try? data.write(to: trackCSVURL, options: writeOptions)
        }
    }

    // MARK: - Option lists

    /// Add a species to the dropdown list (stored lowercase, matching the analysis schema).
    func noteSpecies(_ s: String) {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !v.isEmpty, !knownSpecies.contains(v) else { return }
        knownSpecies.append(v)
    }

    /// Add a lure color to the dropdown list (case-insensitive de-dupe, free text).
    func noteLureColor(_ c: String) {
        let v = c.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty,
              !knownLureColors.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame })
        else { return }
        knownLureColors.append(v)
    }

    // MARK: - Export

    /// URLs to share/export. CSVs feed the analysis/replay pipeline; the JSON files are
    /// the perfect-fidelity source of truth (clean phone-migration / re-import copy).
    var exportURLs: [URL] {
        [catchesCSVURL, weightsCSVURL, trackCSVURL, catchesJSONURL, weightsJSONURL].filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}
