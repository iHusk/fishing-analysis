import SwiftUI
import CoreLocation

/// One-tap catch entry. Every field is pre-filled from the store's
/// carry-forward state so a typical save is: open → adjust length → Save.
/// Large steppers replace keyboards for the on-the-water values.
struct CatchEntryView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var loc: LocationManager
    @Environment(\.dismiss) private var dismiss

    /// Called with the freshly persisted catch so the caller can offer Undo.
    let onSaved: (FishCatch) -> Void

    // Local editable state, seeded from carry-forward on appear.
    @State private var fisherman = ""
    @State private var species = "walleye"
    @State private var kept = true
    @State private var lengthIn: Double = 15.0
    @State private var depthFt: Double = 20.0
    @State private var waterTempText = ""
    @State private var lure1 = ""
    @State private var lure2 = ""
    @State private var bait = ""
    @State private var locationName = ""

    @State private var didSeed = false

    private enum AddTarget { case species, lure1, lure2 }
    @State private var addTarget: AddTarget?
    @State private var newOptionText = ""

    var body: some View {
        NavigationStack {
            Form {
                fishermanSection
                measurementSection
                gearSection
                spotSection
                gpsSection
            }
            .navigationTitle("Log Catch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.headline)
                }
            }
            .onAppear(perform: seedFromCarryForward)
            .alert("Add new", isPresented: Binding(
                get: { addTarget != nil },
                set: { if !$0 { addTarget = nil; newOptionText = "" } }
            )) {
                TextField("Name", text: $newOptionText)
                Button("Add") { commitNewOption() }
                Button("Cancel", role: .cancel) { addTarget = nil; newOptionText = "" }
            }
        }
    }

    // MARK: - Sections

    private var fishermanSection: some View {
        Section("Fisherman") {
            if !store.knownFishermen.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.knownFishermen, id: \.self) { name in
                            Button(name) { fisherman = name }
                                .buttonStyle(.bordered)
                                .tint(fisherman == name ? .accentColor : .secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            TextField("Name", text: $fisherman)
                .textInputAutocapitalization(.words)

            optionRow(title: "Species",
                      value: species.capitalized,
                      isEmpty: species.isEmpty,
                      options: store.knownSpecies.map { $0.capitalized },
                      allowNone: false,
                      onPick: { species = $0.lowercased() },
                      onAddNew: { addTarget = .species })
            Toggle("Kept", isOn: $kept)
        }
    }

    private var measurementSection: some View {
        Section("Measurements") {
            Stepper(value: $lengthIn, in: 0...60, step: 0.25) {
                HStack {
                    Text("Length")
                    Spacer()
                    Text(String(format: "%g in", lengthIn))
                        .font(.title3.bold().monospacedDigit())
                }
            }
            Stepper(value: $depthFt, in: 0...300, step: 1) {
                HStack {
                    Text("Depth")
                    Spacer()
                    Text(String(format: "%g ft", depthFt))
                        .font(.title3.bold().monospacedDigit())
                }
            }
            HStack {
                Text("Water temp")
                Spacer()
                TextField("°F (optional)", text: $waterTempText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
        }
    }

    private var gearSection: some View {
        Section("Lure / Bait") {
            optionRow(title: "Lure color 1",
                      value: lure1,
                      isEmpty: lure1.isEmpty,
                      options: store.knownLureColors,
                      allowNone: true,
                      onPick: { lure1 = $0 },
                      onAddNew: { addTarget = .lure1 })
            optionRow(title: "Lure color 2",
                      value: lure2,
                      isEmpty: lure2.isEmpty,
                      options: store.knownLureColors,
                      allowNone: true,
                      onPick: { lure2 = $0 },
                      onAddNew: { addTarget = .lure2 })
            TextField("Bait (optional)", text: $bait)
                .textInputAutocapitalization(.words)
        }
    }

    // MARK: - Reusable dropdown

    private func optionRow(title: String,
                           value: String,
                           isEmpty: Bool,
                           options: [String],
                           allowNone: Bool,
                           onPick: @escaping (String) -> Void,
                           onAddNew: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                if allowNone {
                    Button("— none —") { onPick("") }
                }
                ForEach(options, id: \.self) { opt in
                    Button(opt) { onPick(opt) }
                }
                Divider()
                Button("Add new…", systemImage: "plus") { onAddNew() }
            } label: {
                HStack(spacing: 4) {
                    Text(isEmpty ? "Select" : value)
                        .foregroundStyle(isEmpty ? Color.secondary : Color.primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    private func commitNewOption() {
        let v = newOptionText.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty, let target = addTarget {
            switch target {
            case .species:
                species = v.lowercased()
                store.noteSpecies(species)
            case .lure1:
                lure1 = v
                store.noteLureColor(v)
            case .lure2:
                lure2 = v
                store.noteLureColor(v)
            }
        }
        newOptionText = ""
        addTarget = nil
    }

    private var spotSection: some View {
        Section("Spot") {
            TextField("Location name", text: $locationName)
                .textInputAutocapitalization(.words)
        }
    }

    private var gpsSection: some View {
        Section("GPS tag") {
            HStack {
                Image(systemName: loc.current == nil ? "location.slash" : "location.fill")
                    .foregroundStyle(loc.current == nil ? Color.secondary : Color.green)
                if let c = loc.current {
                    Text(String(format: "%.6f, %.6f  ±%.0f m",
                                c.coordinate.latitude,
                                c.coordinate.longitude,
                                max(c.horizontalAccuracy, 0)))
                        .font(.footnote.monospaced())
                } else {
                    Text("No fix — will save without coordinates")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Seed + Save

    private func seedFromCarryForward() {
        guard !didSeed else { return }
        didSeed = true
        fisherman = store.lastFisherman
        lengthIn = store.lastLength > 0 ? store.lastLength : 15.0
        depthFt = store.lastDepth > 0 ? store.lastDepth : 20.0
        if let t = store.lastWaterTemp {
            waterTempText = String(format: "%g", t)
        }
        lure1 = store.lastLure1
        lure2 = store.lastLure2
        bait = store.lastBait
        locationName = store.lastLocationName
    }

    private func save() {
        let trimmedTemp = waterTempText.trimmingCharacters(in: .whitespaces)
        let waterTempF = trimmedTemp.isEmpty ? nil : Double(trimmedTemp)
        let speciesValue = species.trimmingCharacters(in: .whitespaces).lowercased()

        let newCatch = store.addCatch(
            fisherman: fisherman.trimmingCharacters(in: .whitespaces),
            species: speciesValue.isEmpty ? "walleye" : speciesValue,
            kept: kept,
            lengthIn: lengthIn,
            depthFt: depthFt,
            waterTempF: waterTempF,
            lure1: lure1.trimmingCharacters(in: .whitespaces),
            lure2: lure2.trimmingCharacters(in: .whitespaces),
            bait: bait.trimmingCharacters(in: .whitespaces),
            locationName: locationName.trimmingCharacters(in: .whitespaces),
            loc: loc.current
        )
        onSaved(newCatch)
        dismiss()
    }
}
