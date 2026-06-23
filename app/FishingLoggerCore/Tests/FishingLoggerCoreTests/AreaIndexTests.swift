import XCTest
@testable import FishingLoggerCore

final class AreaIndexTests: XCTestCase {

    /// A unit square area "Test Bay" spanning lon [0,1], lat [0,1],
    /// with the GeoJSON ring closed (first vertex repeated at the end).
    private let squareFixture = """
    {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": { "name": "Test Bay" },
          "geometry": {
            "type": "Polygon",
            "coordinates": [
              [ [0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0] ]
            ]
          }
        }
      ]
    }
    """

    func testPointInsideResolvesToName() {
        let index = AreaIndex(geoJSONString: squareFixture)
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.areaName(lat: 0.5, lon: 0.5), "Test Bay")
    }

    func testPointOutsideReturnsNil() {
        let index = AreaIndex(geoJSONString: squareFixture)
        XCTAssertNil(index.areaName(lat: 5.0, lon: 5.0))     // far away
        XCTAssertNil(index.areaName(lat: 0.5, lon: -0.5))    // just left of the box
    }

    func testBadJSONYieldsEmptyIndex() {
        let index = AreaIndex(geoJSONString: "{ not valid json ]")
        XCTAssertEqual(index.count, 0)
        XCTAssertNil(index.areaName(lat: 0.5, lon: 0.5))
    }

    func testMissingFeaturesKeyYieldsEmptyIndex() {
        let index = AreaIndex(geoJSONString: #"{ "type": "FeatureCollection" }"#)
        XCTAssertEqual(index.count, 0)
    }

    func testMissingFileYieldsEmptyIndex() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).geojson")
        let index = AreaIndex(contentsOf: url)
        XCTAssertEqual(index.count, 0)
        XCTAssertNil(index.areaName(lat: 0.5, lon: 0.5))
    }

    func testEmptyConstant() {
        XCTAssertEqual(AreaIndex.empty.count, 0)
        XCTAssertNil(AreaIndex.empty.areaName(lat: 0, lon: 0))
    }

    func testFeatureMissingNameIsSkipped() {
        let json = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": {},
              "geometry": {
                "type": "Polygon",
                "coordinates": [ [ [0,0],[1,0],[1,1],[0,1],[0,0] ] ]
              }
            }
          ]
        }
        """
        let index = AreaIndex(geoJSONString: json)
        XCTAssertEqual(index.count, 0)
        XCTAssertNil(index.areaName(lat: 0.5, lon: 0.5))
    }

    func testMultiPolygonSupported() {
        let json = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": { "name": "Two Bits" },
              "geometry": {
                "type": "MultiPolygon",
                "coordinates": [
                  [ [ [0,0],[1,0],[1,1],[0,1],[0,0] ] ],
                  [ [ [10,10],[11,10],[11,11],[10,11],[10,10] ] ]
                ]
              }
            }
          ]
        }
        """
        let index = AreaIndex(geoJSONString: json)
        XCTAssertEqual(index.count, 1)
        XCTAssertEqual(index.areaName(lat: 0.5, lon: 0.5), "Two Bits")
        XCTAssertEqual(index.areaName(lat: 10.5, lon: 10.5), "Two Bits")
        XCTAssertNil(index.areaName(lat: 5.0, lon: 5.0))
    }

    /// Sanity check against a real owner-drawn polygon: a point well inside the
    /// "Pump House" area should resolve to that name.
    func testRealPumpHousePolygon() {
        let json = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": { "name": "Pump House" },
              "geometry": {
                "type": "Polygon",
                "coordinates": [
                  [
                    [-100.730721, 44.828618],
                    [-100.743601, 44.820337],
                    [-100.744459, 44.8084],
                    [-100.728832, 44.806817],
                    [-100.718357, 44.823382],
                    [-100.730721, 44.828618]
                  ]
                ]
              }
            }
          ]
        }
        """
        let index = AreaIndex(geoJSONString: json)
        XCTAssertEqual(index.areaName(lat: 44.8185, lon: -100.7315), "Pump House")
        XCTAssertNil(index.areaName(lat: 43.0, lon: -99.0))
    }
}
