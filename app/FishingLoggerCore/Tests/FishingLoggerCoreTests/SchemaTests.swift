import XCTest
@testable import FishingLoggerCore

final class SchemaTests: XCTestCase {

    // A fixed instant: 2024-06-15 13:30:45 UTC.
    // 2024-06-15T13:30:45Z => unix 1718458245.
    private let fixedDate = Date(timeIntervalSince1970: 1_718_458_245)

    private func sampleCatch(
        id: Int = 1,
        kept: Bool = true,
        waterTempF: Double? = 68.5,
        lat: Double? = 44.367123,
        lon: Double? = -100.336987,
        gpsAccuracyM: Double? = 5,
        headingDeg: Double? = 270,
        fisherman: String = "Tyler",
        lureColor1: String = "chartreuse",
        locationName: String = "north flat",
        notes: String = "good fish",
        measuredWtLbs: Double? = nil
    ) -> FishCatch {
        FishCatch(
            id: id,
            uuid: "AAAA-BBBB",
            timestamp: fixedDate,
            weighSessionID: "2024-06-15",
            trip: "2024-06",
            fisherman: fisherman,
            species: "walleye",
            kept: kept,
            lengthIn: 18.25,
            depthFt: 22,
            waterTempF: waterTempF,
            lureColor1: lureColor1,
            lureColor2: "white",
            bait: "crawler",
            locationName: locationName,
            lat: lat,
            lon: lon,
            gpsAccuracyM: gpsAccuracyM,
            headingDeg: headingDeg,
            notes: notes,
            measuredWtLbs: measuredWtLbs
        )
    }

    // MARK: - Headers

    func testCatchesHeaderExact() {
        XCTAssertEqual(
            Schema.catchesHeader,
            "id,uuid,timestamp_local,timestamp_utc,year,weigh_session_id,trip,fisherman,species,kept,length_in,depth_ft,water_temp_f,lure_color1,lure_color2,bait,location_name,lat,lon,gps_accuracy_m,heading_deg,measured_wt_lbs,notes"
        )
    }

    func testWeightsHeaderExact() {
        XCTAssertEqual(
            Schema.weightsHeader,
            "weigh_session_id,weigh_date,trip,daily_wt_lbs,day_inches,daily_wt_per_inch,n_catches_logged,notes"
        )
    }

    func testTrackHeaderExact() {
        XCTAssertEqual(
            Schema.trackHeader,
            "timestamp_utc,timestamp_local,trip,weigh_session_id,lat,lon,accuracy_m,altitude_m,speed_mps,course_deg"
        )
    }

    // MARK: - Full catches row, every column in order

    func testCatchesCSVFullRow() {
        let csv = Schema.catchesCSV([sampleCatch()])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        // header, row, trailing empty (csv ends with newline)
        XCTAssertEqual(lines.first.map(String.init), Schema.catchesHeader)
        XCTAssertTrue(csv.hasSuffix("\n"))

        let row = String(lines[1])
        let utc = DateFmt.utcStamp(fixedDate)        // deterministic: 2024-06-15 13:30:45
        let local = DateFmt.localStamp(fixedDate)    // local tz, no suffix
        XCTAssertEqual(utc, "2024-06-15 13:30:45")
        // local stamp must NOT carry a timezone suffix (only date + time chars)
        XCTAssertFalse(local.contains("+"))
        XCTAssertFalse(local.contains("Z"))
        XCTAssertEqual(local.count, "yyyy-MM-dd HH:mm:ss".count)

        let expected = [
            "1",
            "AAAA-BBBB",
            local,
            utc,
            "2024",
            "2024-06-15",
            "2024-06",
            "Tyler",
            "walleye",
            "true",
            "18.25",
            "22",
            "68.5",
            "chartreuse",
            "white",
            "crawler",
            "north flat",
            "44.367123",
            "-100.336987",
            "5",
            "270",
            "",          // measured_wt_lbs (nil by default)
            "good fish"
        ].joined(separator: ",")
        XCTAssertEqual(row, expected)
    }

    // MARK: - Number formatting + blanks

    func testBlankOptionalsAndNumberFormatting() {
        let c = sampleCatch(waterTempF: nil, lat: nil, lon: nil, gpsAccuracyM: nil, headingDeg: nil)
        let line = Schema.catchLine(c)
        let cols = line.components(separatedBy: ",")
        // water_temp_f index 12, lat 17, lon 18, gps_accuracy_m 19, heading_deg 20
        XCTAssertEqual(cols[12], "")  // water_temp_f
        XCTAssertEqual(cols[17], "")  // lat
        XCTAssertEqual(cols[18], "")  // lon
        XCTAssertEqual(cols[19], "")  // gps_accuracy_m
        XCTAssertEqual(cols[20], "")  // heading_deg
    }

    func testNumberFormatUsesG() {
        // 22.0 should render "22" (%g), 18.25 stays "18.25"
        let c = sampleCatch()
        let line = Schema.catchLine(c)
        let cols = line.components(separatedBy: ",")
        XCTAssertEqual(cols[10], "18.25") // length_in
        XCTAssertEqual(cols[11], "22")    // depth_ft (22.0 -> "22")
    }

    func testLatLonSixDecimals() {
        let c = sampleCatch(lat: 44.3, lon: -100)
        let line = Schema.catchLine(c)
        let cols = line.components(separatedBy: ",")
        XCTAssertEqual(cols[17], "44.300000")
        XCTAssertEqual(cols[18], "-100.000000")
    }

    func testWeightColumnRendersAndBlank() {
        // measured_wt_lbs is the 22nd column (index 21), immediately before notes (22).
        let withWeight = Schema.catchLine(sampleCatch(measuredWtLbs: 1.8))
            .components(separatedBy: ",")
        XCTAssertEqual(withWeight[21], "1.8")   // measured_wt_lbs
        XCTAssertEqual(withWeight[22], "good fish") // notes stays the final column

        let noWeight = Schema.catchLine(sampleCatch(measuredWtLbs: nil))
            .components(separatedBy: ",")
        XCTAssertEqual(noWeight[21], "")        // blank when nil
    }

    func testKeptTrueFalse() {
        XCTAssertTrue(Schema.catchLine(sampleCatch(kept: true)).components(separatedBy: ",")[9] == "true")
        XCTAssertTrue(Schema.catchLine(sampleCatch(kept: false)).components(separatedBy: ",")[9] == "false")
    }

    // MARK: - CSV escaping

    func testEscapeComma() {
        let c = sampleCatch(notes: "two fish, both kept")
        let line = Schema.catchLine(c)
        XCTAssertTrue(line.hasSuffix("\"two fish, both kept\""))
    }

    func testEscapeQuote() {
        let c = sampleCatch(locationName: "the \"honey hole\"")
        let line = Schema.catchLine(c)
        XCTAssertTrue(line.contains("\"the \"\"honey hole\"\"\""))
    }

    func testEscapeNewline() {
        let c = sampleCatch(notes: "line1\nline2")
        let line = Schema.catchLine(c)
        XCTAssertTrue(line.contains("\"line1\nline2\""))
    }

    func testNoEscapeWhenClean() {
        let c = sampleCatch(fisherman: "Tyler")
        let cols = Schema.catchLine(c).components(separatedBy: ",")
        XCTAssertEqual(cols[7], "Tyler") // no surrounding quotes
    }

    // MARK: - daily_weights.csv

    private func sampleWeight(dayInches: Double? = 200, dailyWtLbs: Double = 50) -> DailyWeight {
        DailyWeight(
            weighSessionID: "2024-06-15",
            weighDate: fixedDate,
            trip: "2024-06",
            dailyWtLbs: dailyWtLbs,
            dayInches: dayInches,
            notes: "bag"
        )
    }

    func testWeightsCSVPerInchAndCount() {
        let csv = Schema.weightsCSV([sampleWeight(dayInches: 200, dailyWtLbs: 50)],
                                    catchCounts: ["2024-06-15": 11])
        let row = String(csv.split(separator: "\n")[1])
        let cols = row.components(separatedBy: ",")
        // weigh_session_id, weigh_date, trip, daily_wt_lbs, day_inches, daily_wt_per_inch, n_catches_logged, notes
        XCTAssertEqual(cols[0], "2024-06-15")
        XCTAssertEqual(cols[1], DateFmt.dayKey(fixedDate))
        XCTAssertEqual(cols[2], "2024-06")
        XCTAssertEqual(cols[3], "50")
        XCTAssertEqual(cols[4], "200")
        XCTAssertEqual(cols[5], "0.25")  // 50/200
        XCTAssertEqual(cols[6], "11")
        XCTAssertEqual(cols[7], "bag")
    }

    func testWeightsCSVPerInchBlankWhenNil() {
        let csv = Schema.weightsCSV([sampleWeight(dayInches: nil)],
                                    catchCounts: [:])
        let cols = String(csv.split(separator: "\n")[1]).components(separatedBy: ",")
        XCTAssertEqual(cols[4], "")  // day_inches blank
        XCTAssertEqual(cols[5], "")  // daily_wt_per_inch blank
        XCTAssertEqual(cols[6], "0") // missing count -> 0
    }

    func testWeightsCSVPerInchBlankWhenZeroInches() {
        let csv = Schema.weightsCSV([sampleWeight(dayInches: 0)], catchCounts: [:])
        let cols = String(csv.split(separator: "\n")[1]).components(separatedBy: ",")
        XCTAssertEqual(cols[5], "")  // avoid divide-by-zero
    }

    // MARK: - track

    func testTrackLine() {
        let p = TrackPoint(
            timestamp: fixedDate,
            trip: "2024-06",
            weighSessionID: "2024-06-15",
            lat: 44.367123,
            lon: -100.336987,
            accuracyM: 8,
            altitudeM: 487.5,
            speedMps: 2.3,
            courseDeg: nil
        )
        let line = Schema.trackLine(p)
        let cols = line.components(separatedBy: ",")
        XCTAssertEqual(cols[0], "2024-06-15 13:30:45") // utc
        XCTAssertEqual(cols[2], "2024-06")
        XCTAssertEqual(cols[3], "2024-06-15")
        XCTAssertEqual(cols[4], "44.367123")
        XCTAssertEqual(cols[5], "-100.336987")
        XCTAssertEqual(cols[6], "8")
        XCTAssertEqual(cols[7], "487.5")
        XCTAssertEqual(cols[8], "2.3")
        XCTAssertEqual(cols[9], "")  // nil course
    }
}
