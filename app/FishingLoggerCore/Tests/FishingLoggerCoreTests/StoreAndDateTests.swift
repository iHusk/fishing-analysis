import XCTest
@testable import FishingLoggerCore

final class StoreAndDateTests: XCTestCase {

    private let fixedDate = Date(timeIntervalSince1970: 1_718_458_245) // 2024-06-15 13:30:45 UTC

    private func sampleCatch(id: Int, kept: Bool) -> FishCatch {
        FishCatch(
            id: id,
            uuid: "U\(id)",
            timestamp: fixedDate,
            weighSessionID: "2024-06-15",
            trip: "2024-06",
            fisherman: "Tyler",
            species: "walleye",
            kept: kept,
            lengthIn: 18.25,
            depthFt: 22,
            waterTempF: 68.5,
            lureColor1: "chartreuse",
            lureColor2: "white",
            bait: "crawler",
            locationName: "north flat",
            lat: 44.367123,
            lon: -100.336987,
            gpsAccuracyM: 5,
            headingDeg: 270,
            notes: "n"
        )
    }

    // MARK: - DateFmt

    func testUtcStampDeterministic() {
        XCTAssertEqual(DateFmt.utcStamp(fixedDate), "2024-06-15 13:30:45")
    }

    func testLocalStampNoTimezoneSuffix() {
        let s = DateFmt.localStamp(fixedDate)
        XCTAssertEqual(s.count, "yyyy-MM-dd HH:mm:ss".count)
        XCTAssertFalse(s.contains("Z"))
        XCTAssertFalse(s.contains("+"))
        XCTAssertFalse(s.contains("GMT"))
        // Must equal a same-config POSIX formatter in the current timezone.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone.current
        XCTAssertEqual(s, f.string(from: fixedDate))
    }

    func testYearKey() {
        XCTAssertEqual(DateFmt.year(fixedDate), "2024")
    }

    func testTripKeyFormat() {
        // tripKey is local "yyyy-MM"; assert it matches a same-config formatter.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone.current
        XCTAssertEqual(DateFmt.tripKey(fixedDate), f.string(from: fixedDate))
    }

    func testDayKeyFormat() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        XCTAssertEqual(DateFmt.dayKey(fixedDate), f.string(from: fixedDate))
    }

    // MARK: - CatchStore round-trip

    func testCatchStoreRoundTrip() throws {
        let rows = [sampleCatch(id: 1, kept: true), sampleCatch(id: 2, kept: false)]
        let data = try CatchStore.encode(rows)
        let back = try CatchStore.decode(data)
        XCTAssertEqual(rows, back)
    }

    func testCatchStoreRoundTripWithNils() throws {
        var c = sampleCatch(id: 3, kept: true)
        c.waterTempF = nil
        c.lat = nil
        c.lon = nil
        c.gpsAccuracyM = nil
        c.headingDeg = nil
        let data = try CatchStore.encode([c])
        let back = try CatchStore.decode(data)
        XCTAssertEqual([c], back)
    }

    // MARK: - WeightStore round-trip

    func testWeightStoreRoundTrip() throws {
        let w = DailyWeight(
            weighSessionID: "2024-06-15",
            weighDate: fixedDate,
            trip: "2024-06",
            dailyWtLbs: 50,
            dayInches: 200,
            notes: "bag"
        )
        let w2 = DailyWeight(
            weighSessionID: "2024-06-16",
            weighDate: fixedDate,
            trip: "2024-06",
            dailyWtLbs: 40,
            dayInches: nil,
            notes: ""
        )
        let data = try WeightStore.encode([w, w2])
        let back = try WeightStore.decode(data)
        XCTAssertEqual([w, w2], back)
    }

    func testStoresUseISO8601Dates() throws {
        let data = try CatchStore.encode([sampleCatch(id: 1, kept: true)])
        let json = String(data: data, encoding: .utf8) ?? ""
        // ISO8601 encoding of 2024-06-15T13:30:45Z
        XCTAssertTrue(json.contains("2024-06-15T13:30:45Z"), "JSON should carry ISO8601 date, got: \(json)")
    }

    // MARK: - keptOnly

    func testKeptOnlyFilters() {
        let rows = [
            sampleCatch(id: 1, kept: true),
            sampleCatch(id: 2, kept: false),
            sampleCatch(id: 3, kept: true)
        ]
        let kept = keptOnly(rows)
        XCTAssertEqual(kept.map(\.id), [1, 3])
    }

    func testKeptOnlyEmpty() {
        XCTAssertTrue(keptOnly([]).isEmpty)
    }
}
