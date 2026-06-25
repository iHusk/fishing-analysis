import Foundation

/// One logged fish. Pure Foundation so it compiles on macOS (tests) and iOS (app).
public struct FishCatch: Codable, Equatable, Identifiable {
    public var id: Int
    public var uuid: String
    public var timestamp: Date
    public var weighSessionID: String
    public var trip: String
    public var fisherman: String
    public var species: String
    public var kept: Bool
    public var lengthIn: Double
    public var depthFt: Double
    public var waterTempF: Double?
    public var lureColor1: String
    public var lureColor2: String
    public var bait: String
    public var locationName: String
    public var lat: Double?
    public var lon: Double?
    public var gpsAccuracyM: Double?
    public var headingDeg: Double?
    public var notes: String
    /// Measured per-catch weight in pounds (optional; blank in all pre-2026 data).
    /// Go-forward schema addition (2026-06) — NOT computed; ground-truth for the
    /// length→weight model calibration.
    public var measuredWtLbs: Double?

    public init(
        id: Int,
        uuid: String,
        timestamp: Date,
        weighSessionID: String,
        trip: String,
        fisherman: String,
        species: String,
        kept: Bool,
        lengthIn: Double,
        depthFt: Double,
        waterTempF: Double?,
        lureColor1: String,
        lureColor2: String,
        bait: String,
        locationName: String,
        lat: Double?,
        lon: Double?,
        gpsAccuracyM: Double?,
        headingDeg: Double?,
        notes: String,
        measuredWtLbs: Double? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.timestamp = timestamp
        self.weighSessionID = weighSessionID
        self.trip = trip
        self.fisherman = fisherman
        self.species = species
        self.kept = kept
        self.lengthIn = lengthIn
        self.depthFt = depthFt
        self.waterTempF = waterTempF
        self.lureColor1 = lureColor1
        self.lureColor2 = lureColor2
        self.bait = bait
        self.locationName = locationName
        self.lat = lat
        self.lon = lon
        self.gpsAccuracyM = gpsAccuracyM
        self.headingDeg = headingDeg
        self.notes = notes
        self.measuredWtLbs = measuredWtLbs
    }
}

/// One weigh session = the ground-truth daily bag weight.
public struct DailyWeight: Codable, Equatable, Identifiable {
    public var weighSessionID: String
    public var weighDate: Date
    public var trip: String
    public var dailyWtLbs: Double
    public var dayInches: Double?
    public var notes: String

    public var id: String { weighSessionID }

    public init(
        weighSessionID: String,
        weighDate: Date,
        trip: String,
        dailyWtLbs: Double,
        dayInches: Double?,
        notes: String
    ) {
        self.weighSessionID = weighSessionID
        self.weighDate = weighDate
        self.trip = trip
        self.dailyWtLbs = dailyWtLbs
        self.dayInches = dayInches
        self.notes = notes
    }
}

/// One GPS fix on the boat's daily travel track.
public struct TrackPoint: Codable, Equatable {
    public var timestamp: Date
    public var trip: String
    public var weighSessionID: String
    public var lat: Double
    public var lon: Double
    public var accuracyM: Double
    public var altitudeM: Double
    public var speedMps: Double?
    public var courseDeg: Double?

    public init(
        timestamp: Date,
        trip: String,
        weighSessionID: String,
        lat: Double,
        lon: Double,
        accuracyM: Double,
        altitudeM: Double,
        speedMps: Double?,
        courseDeg: Double?
    ) {
        self.timestamp = timestamp
        self.trip = trip
        self.weighSessionID = weighSessionID
        self.lat = lat
        self.lon = lon
        self.accuracyM = accuracyM
        self.altitudeM = altitudeM
        self.speedMps = speedMps
        self.courseDeg = courseDeg
    }
}

/// Kept fish only — the bag-calibration denominator (released fish excluded).
public func keptOnly(_ rows: [FishCatch]) -> [FishCatch] {
    rows.filter { $0.kept }
}
