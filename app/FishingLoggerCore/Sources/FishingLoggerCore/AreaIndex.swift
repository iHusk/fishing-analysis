import Foundation

/// Point-in-polygon lookup over the owner-drawn lake-area polygons.
///
/// Pure Foundation (no CoreLocation/UIKit) so it unit-tests on macOS and runs on iOS.
/// Parses a GeoJSON FeatureCollection of `Polygon` (and optionally `MultiPolygon`)
/// features, each with `properties.name`, and resolves a lat/lon to the name of the
/// first containing area via a ray-casting point-in-polygon test.
///
/// Robustness contract: a missing file or malformed JSON yields an EMPTY index
/// (zero areas). No initializer or lookup ever throws to the caller; bad input
/// simply means `areaName(lat:lon:)` returns nil.
public struct AreaIndex {

    /// A single named area: its outer ring(s), each ring an array of (lon, lat) points.
    /// A simple Polygon contributes one ring; a MultiPolygon contributes one per part.
    private struct Area {
        let name: String
        /// Outer rings only (holes are ignored — the owner's areas don't use them).
        let rings: [[(lon: Double, lat: Double)]]
    }

    private let areas: [Area]

    /// Number of named areas successfully parsed (0 for a missing/bad source).
    public var count: Int { areas.count }

    // MARK: - Construction

    private init(areas: [Area]) {
        self.areas = areas
    }

    /// An empty index that resolves every coordinate to nil.
    public static let empty = AreaIndex(areas: [])

    /// Build from raw GeoJSON `Data`. Never throws — bad input -> `.empty`.
    public init(geoJSON data: Data) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data),
            let obj = root as? [String: Any],
            let features = obj["features"] as? [[String: Any]]
        else {
            self = .empty
            return
        }

        var parsed: [Area] = []
        for feature in features {
            guard
                let props = feature["properties"] as? [String: Any],
                let name = props["name"] as? String,
                let geometry = feature["geometry"] as? [String: Any],
                let type = geometry["type"] as? String
            else { continue }

            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let rings = AreaIndex.outerRings(type: type, coordinates: geometry["coordinates"])
            guard !rings.isEmpty else { continue }
            parsed.append(Area(name: trimmed, rings: rings))
        }
        self = AreaIndex(areas: parsed)
    }

    /// Build from a GeoJSON string. Never throws — bad input -> `.empty`.
    public init(geoJSONString string: String) {
        self.init(geoJSON: Data(string.utf8))
    }

    /// Build from a file URL. A missing/unreadable file -> `.empty`.
    public init(contentsOf url: URL) {
        if let data = try? Data(contentsOf: url) {
            self.init(geoJSON: data)
        } else {
            self = .empty
        }
    }

    // MARK: - Lookup

    /// Name of the first area whose outer ring contains the point, or nil.
    public func areaName(lat: Double, lon: Double) -> String? {
        for area in areas {
            for ring in area.rings where AreaIndex.contains(ring: ring, lat: lat, lon: lon) {
                return area.name
            }
        }
        return nil
    }

    // MARK: - GeoJSON coordinate parsing

    /// Extract the outer ring(s) for a Polygon or MultiPolygon geometry.
    /// GeoJSON rings are `[[lon, lat], ...]`; the first ring of a Polygon is the
    /// outer boundary, remaining rings are holes (ignored here).
    private static func outerRings(type: String, coordinates: Any?) -> [[(lon: Double, lat: Double)]] {
        switch type {
        case "Polygon":
            // coordinates: [ ring, hole?, ... ] -> take the outer ring only.
            guard let poly = coordinates as? [[[Double]]], let outer = poly.first else { return [] }
            let ring = points(from: outer)
            return ring.isEmpty ? [] : [ring]
        case "MultiPolygon":
            // coordinates: [ polygon, ... ] where polygon = [ ring, hole?, ... ].
            guard let multi = coordinates as? [[[[Double]]]] else { return [] }
            var rings: [[(lon: Double, lat: Double)]] = []
            for poly in multi {
                guard let outer = poly.first else { continue }
                let ring = points(from: outer)
                if !ring.isEmpty { rings.append(ring) }
            }
            return rings
        default:
            return []
        }
    }

    /// Convert `[[lon, lat], ...]` to typed points, dropping malformed entries.
    private static func points(from ring: [[Double]]) -> [(lon: Double, lat: Double)] {
        var out: [(lon: Double, lat: Double)] = []
        out.reserveCapacity(ring.count)
        for pair in ring where pair.count >= 2 {
            out.append((lon: pair[0], lat: pair[1]))
        }
        return out
    }

    // MARK: - Ray casting

    /// Standard even-odd ray-casting test. Treats the ring as closed regardless of
    /// whether the GeoJSON repeats the first vertex at the end.
    private static func contains(ring: [(lon: Double, lat: Double)], lat: Double, lon: Double) -> Bool {
        let n = ring.count
        guard n >= 3 else { return false }
        var inside = false
        var j = n - 1
        for i in 0..<n {
            let xi = ring[i].lon, yi = ring[i].lat
            let xj = ring[j].lon, yj = ring[j].lat
            if (yi > lat) != (yj > lat) {
                let slope = (xj - xi) / (yj - yi)
                let xIntersect = xi + (lat - yi) * slope
                if lon < xIntersect { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}
