import Foundation

/// CSV serialization for the LOCKED go-forward schema.
/// Column order and names here are the contract the analysis pipeline reads.
public enum Schema {

    // MARK: - Field formatting helpers

    /// CSV-escape a field: wrap in double-quotes and double internal quotes
    /// whenever it contains a comma, quote, or newline.
    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    /// A general Double via "%g" (compact). Used for most numeric columns.
    static func num(_ x: Double) -> String {
        String(format: "%g", x)
    }

    /// Optional Double via "%g", blank when nil.
    static func numOpt(_ x: Double?) -> String {
        guard let x = x else { return "" }
        return String(format: "%g", x)
    }

    /// Latitude/longitude formatted "%.6f", blank when nil.
    static func coordOpt(_ x: Double?) -> String {
        guard let x = x else { return "" }
        return String(format: "%.6f", x)
    }

    /// Join already-escaped fields into a CSV record.
    static func row(_ fields: [String]) -> String {
        fields.joined(separator: ",")
    }

    // MARK: - catches.csv

    // NOTE: `measured_wt_lbs` (2026-06 addition) is inserted just before `notes` so the
    // free-text `notes` stays the final column. Readers MUST key by header name, not
    // position — pre-2026 files lack this column and have `notes` one slot earlier.
    public static let catchesHeader =
        "id,uuid,timestamp_local,timestamp_utc,year,weigh_session_id,trip,fisherman,species,kept,length_in,depth_ft,water_temp_f,lure_color1,lure_color2,bait,location_name,lat,lon,gps_accuracy_m,heading_deg,measured_wt_lbs,notes"

    public static func catchLine(_ c: FishCatch) -> String {
        let fields: [String] = [
            num(Double(c.id)),
            escape(c.uuid),
            escape(DateFmt.localStamp(c.timestamp)),
            escape(DateFmt.utcStamp(c.timestamp)),
            escape(DateFmt.year(c.timestamp)),
            escape(c.weighSessionID),
            escape(c.trip),
            escape(c.fisherman),
            escape(c.species),
            c.kept ? "true" : "false",
            num(c.lengthIn),
            num(c.depthFt),
            numOpt(c.waterTempF),
            escape(c.lureColor1),
            escape(c.lureColor2),
            escape(c.bait),
            escape(c.locationName),
            coordOpt(c.lat),
            coordOpt(c.lon),
            numOpt(c.gpsAccuracyM),
            numOpt(c.headingDeg),
            numOpt(c.measuredWtLbs),
            escape(c.notes)
        ]
        return row(fields)
    }

    public static func catchesCSV(_ rows: [FishCatch]) -> String {
        var lines = [catchesHeader]
        for c in rows { lines.append(catchLine(c)) }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - daily_weights.csv

    public static let weightsHeader =
        "weigh_session_id,weigh_date,trip,daily_wt_lbs,day_inches,daily_wt_per_inch,n_catches_logged,notes"

    public static func weightLine(_ w: DailyWeight, nCatches: Int) -> String {
        let perInch: String
        if let inches = w.dayInches, inches > 0 {
            perInch = num(w.dailyWtLbs / inches)
        } else {
            perInch = ""
        }
        let fields: [String] = [
            escape(w.weighSessionID),
            escape(DateFmt.dayKey(w.weighDate)),
            escape(w.trip),
            num(w.dailyWtLbs),
            numOpt(w.dayInches),
            perInch,
            num(Double(nCatches)),
            escape(w.notes)
        ]
        return row(fields)
    }

    public static func weightsCSV(_ rows: [DailyWeight], catchCounts: [String: Int]) -> String {
        var lines = [weightsHeader]
        for w in rows {
            let n = catchCounts[w.weighSessionID] ?? 0
            lines.append(weightLine(w, nCatches: n))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - track.csv

    public static let trackHeader =
        "timestamp_utc,timestamp_local,trip,weigh_session_id,lat,lon,accuracy_m,altitude_m,speed_mps,course_deg"

    public static func trackLine(_ p: TrackPoint) -> String {
        let fields: [String] = [
            escape(DateFmt.utcStamp(p.timestamp)),
            escape(DateFmt.localStamp(p.timestamp)),
            escape(p.trip),
            escape(p.weighSessionID),
            coordOpt(p.lat),
            coordOpt(p.lon),
            num(p.accuracyM),
            num(p.altitudeM),
            numOpt(p.speedMps),
            numOpt(p.courseDeg)
        ]
        return row(fields)
    }
}
