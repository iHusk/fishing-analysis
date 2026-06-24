import Foundation
import Combine

/// Per-angler defaults — a small, fast "remember what this person usually does"
/// layer that lives entirely SEPARATE from the catch data.
///
/// This model NEVER touches `catches.csv` / `catches.json` or the locked `Schema`.
/// Its only on-disk artifact is `profiles.json` in the app's Documents directory.
/// Losing or corrupting this file costs nothing but a round of re-learning — it is
/// pure convenience state, not a source of truth.
struct AnglerProfile: Codable, Equatable {
    /// Original-cased display name (the map key is the lowercased form of this).
    var fisherman: String
    var species: String
    var lure1: String
    var lure2: String
    var bait: String
    var lengthIn: Double
    var depthFt: Double
    var waterTempF: Double?
    var locationName: String
}

/// Stores and persists each angler's last-used defaults, keyed by lowercased name.
///
/// Durability model mirrors `Store` exactly:
///   - `profiles.json` is the single file, encoded pretty-printed.
///   - Every write is `.atomic` + `.completeFileProtectionUntilFirstUserAuthentication`
///     so it succeeds while the phone is locked and can never half-write.
/// Loading tolerates a missing or corrupt file by simply starting empty.
@MainActor
final class AnglerProfileStore: ObservableObject {

    // MARK: - Published state

    /// Angler defaults keyed by `fisherman.lowercased()`. The struct itself
    /// carries the original-cased name for display.
    @Published private(set) var profiles: [String: AnglerProfile] = [:]

    // MARK: - File location

    private let docs: URL
    private let profilesJSONURL: URL

    /// Atomic + file-protection write options, matching `Store`.
    private let writeOptions: Data.WritingOptions =
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    // MARK: - Init

    init() {
        let fm = FileManager.default
        // Same sandboxed, Files-app-visible Documents directory the catch store uses.
        self.docs = (try? fm.url(for: .documentDirectory,
                                 in: .userDomainMask,
                                 appropriateFor: nil,
                                 create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        self.profilesJSONURL = docs.appendingPathComponent("profiles.json")

        load()
    }

    // MARK: - Loading

    /// Load `profiles.json` if present. Missing or corrupt file => start empty.
    private func load() {
        guard
            let data = try? Data(contentsOf: profilesJSONURL),
            let decoded = try? JSONDecoder().decode([String: AnglerProfile].self, from: data)
        else { return }
        profiles = decoded
    }

    // MARK: - Lookup

    /// Case-insensitive lookup of an angler's remembered defaults.
    func profile(for fisherman: String) -> AnglerProfile? {
        profiles[key(for: fisherman)]
    }

    // MARK: - Remember

    /// Upsert this angler's defaults from a just-saved catch, then persist.
    /// Maps the catch's lure fields onto the profile's `lure1` / `lure2`.
    func remember(from c: FishCatch) {
        let k = key(for: c.fisherman)
        guard !k.isEmpty else { return }

        profiles[k] = AnglerProfile(
            fisherman: c.fisherman,
            species: c.species,
            lure1: c.lureColor1,
            lure2: c.lureColor2,
            bait: c.bait,
            lengthIn: c.lengthIn,
            depthFt: c.depthFt,
            waterTempF: c.waterTempF,
            locationName: c.locationName
        )

        persist()
    }

    // MARK: - Helpers

    /// Normalized map key: trimmed + lowercased name.
    private func key(for fisherman: String) -> String {
        fisherman
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    // MARK: - Persistence

    /// Rewrite `profiles.json` atomically with full file protection.
    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: profilesJSONURL, options: writeOptions)
    }
}
