import SwiftUI
import UIKit

/// Daily weigh-in — the one ground-truth number for the bag-calibration model.
/// Records `daily_wt_lbs` for the active weigh session, with an optional
/// independently-measured `day_inches` that the loader cross-checks.
struct WeighInView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var dailyWtText = ""
    @State private var dayInchesText = ""
    @State private var notes = ""
    @State private var didSeed = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Session", value: store.activeSessionID.isEmpty ? "—" : store.activeSessionID)
                LabeledContent("Trip", value: store.activeTrip.isEmpty ? "—" : store.activeTrip)
                LabeledContent("Catches logged", value: "\(sessionCatchCount)")
            } header: {
                Text("Active session")
            } footer: {
                Text("Bag weight is the whole boat's kept fish for this session.")
            }

            Section("Bag") {
                HStack {
                    Text("Daily bag")
                    Spacer()
                    TextField("lbs", text: $dailyWtText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                    Text("lbs").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Bag inches")
                    Spacer()
                    TextField("optional", text: $dayInchesText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                    Text("in").foregroundStyle(.secondary)
                }
            }

            if let summed = summedKeptInches {
                Section {
                    LabeledContent("Sum of kept lengths",
                                   value: String(format: "%g in", summed))
                    if let entered = Double(dayInchesText.trimmingCharacters(in: .whitespaces)),
                       entered > 0,
                       abs(entered - summed) / max(summed, 1) > 0.1 {
                        Label("Measured inches differ >10% from logged sum",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("Cross-check only — the measured bag inches stays the source of truth.")
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(1...4)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .font(.headline)
                    .disabled(parsedWeight == nil)
            }
        }
        .onAppear(perform: seedFromExisting)
    }

    // MARK: - Derived

    private var sessionCatchCount: Int {
        store.catches.filter { $0.weighSessionID == store.activeSessionID }.count
    }

    /// Sum of lengths of kept fish in this session (the auto-sum cross-check).
    private var summedKeptInches: Double? {
        let kept = keptOnly(store.catches.filter { $0.weighSessionID == store.activeSessionID })
        guard !kept.isEmpty else { return nil }
        return kept.reduce(0) { $0 + $1.lengthIn }
    }

    private var parsedWeight: Double? {
        Double(dailyWtText.trimmingCharacters(in: .whitespaces))
    }

    // MARK: - Seed + Save

    private func seedFromExisting() {
        guard !didSeed else { return }
        didSeed = true
        if let existing = store.weights.first(where: { $0.weighSessionID == store.activeSessionID }) {
            dailyWtText = String(format: "%g", existing.dailyWtLbs)
            if let inches = existing.dayInches {
                dayInchesText = String(format: "%g", inches)
            }
            notes = existing.notes
        }
    }

    private func save() {
        guard let weight = parsedWeight else { return }
        let inches = Double(dayInchesText.trimmingCharacters(in: .whitespaces))
        let weight0 = DailyWeight(
            weighSessionID: store.activeSessionID,
            weighDate: Date(),
            trip: store.activeTrip,
            dailyWtLbs: weight,
            dayInches: (inches ?? 0) > 0 ? inches : nil,
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        store.saveWeight(weight0)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        dismiss()
    }
}
