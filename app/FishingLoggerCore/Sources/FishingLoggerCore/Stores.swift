import Foundation

/// JSON persistence for catches. Source-of-truth file is catches.json.
/// Uses ISO8601 dates so the on-disk format is stable and inspectable.
public enum CatchStore {
    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ rows: [FishCatch]) throws -> Data {
        try encoder().encode(rows)
    }

    public static func decode(_ data: Data) throws -> [FishCatch] {
        try decoder().decode([FishCatch].self, from: data)
    }
}

/// JSON persistence for daily weigh sessions. Source-of-truth file is weights.json.
public enum WeightStore {
    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ rows: [DailyWeight]) throws -> Data {
        try encoder().encode(rows)
    }

    public static func decode(_ data: Data) throws -> [DailyWeight] {
        try decoder().decode([DailyWeight].self, from: data)
    }
}
