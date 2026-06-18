import Foundation

/// Date/time formatting for the locked CSV schema.
/// All formatters use a fixed POSIX locale so output is stable regardless of device settings.
public enum DateFmt {
    private static let posix = Locale(identifier: "en_US_POSIX")

    private static func makeFormatter(_ format: String, utc: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = format
        f.timeZone = utc ? TimeZone(identifier: "UTC") : TimeZone.current
        return f
    }

    /// Local wall-clock "yyyy-MM-dd HH:mm:ss" with NO timezone suffix.
    public static func localStamp(_ date: Date) -> String {
        makeFormatter("yyyy-MM-dd HH:mm:ss", utc: false).string(from: date)
    }

    /// UTC "yyyy-MM-dd HH:mm:ss".
    public static func utcStamp(_ date: Date) -> String {
        makeFormatter("yyyy-MM-dd HH:mm:ss", utc: true).string(from: date)
    }

    /// "yyyy-MM-dd" in local time.
    public static func dayKey(_ date: Date) -> String {
        makeFormatter("yyyy-MM-dd", utc: false).string(from: date)
    }

    /// "yyyy-MM" in local time.
    public static func tripKey(_ date: Date) -> String {
        makeFormatter("yyyy-MM", utc: false).string(from: date)
    }

    /// "yyyy" of the timestamp in local time.
    public static func year(_ date: Date) -> String {
        makeFormatter("yyyy", utc: false).string(from: date)
    }
}
