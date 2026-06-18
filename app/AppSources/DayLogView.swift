import SwiftUI
import UIKit

/// Scrollable, editable list of today's catches (active session, newest first).
/// Swipe to delete; tap to edit. Back-dating and corrections are first-class.
struct DayLogView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            if store.todaysCatches.isEmpty {
                ContentUnavailableView(
                    "No catches yet",
                    systemImage: "fish",
                    description: Text("Logged catches for this session appear here.")
                )
            } else {
                Section {
                    ForEach(store.todaysCatches) { item in
                        NavigationLink {
                            EditCatchView(item: item)
                                .environmentObject(store)
                        } label: {
                            CatchRow(item: item)
                        }
                    }
                    .onDelete(perform: deleteRows)
                } header: {
                    Text("\(store.todaysCatches.count) fish — session \(store.activeSessionID)")
                }
            }
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        let rows = store.todaysCatches
        for index in offsets {
            store.deleteCatch(rows[index])
        }
    }
}

/// Compact summary row for the day log.
private struct CatchRow: View {
    let item: FishCatch

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.species.capitalized)
                        .font(.headline)
                    if !item.kept {
                        Text("released")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(detailLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DateFmt.localStamp(item.timestamp).suffix(8))
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var detailLine: String {
        var parts: [String] = [String(format: "%g in", item.lengthIn),
                               String(format: "%g ft", item.depthFt)]
        if !item.fisherman.isEmpty { parts.insert(item.fisherman, at: 0) }
        return parts.joined(separator: " · ")
    }
}

/// Full editor for a single catch. Edits commit through `store.updateCatch`.
struct EditCatchView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State var item: FishCatch
    @State private var waterTempText = ""
    @State private var didSeed = false

    var body: some View {
        Form {
            Section("Fisherman / Species") {
                TextField("Fisherman", text: $item.fisherman)
                    .textInputAutocapitalization(.words)
                TextField("Species", text: $item.species)
                    .textInputAutocapitalization(.never)
                Toggle("Kept", isOn: $item.kept)
            }

            Section("Measurements") {
                Stepper(value: $item.lengthIn, in: 0...60, step: 0.25) {
                    HStack {
                        Text("Length")
                        Spacer()
                        Text(String(format: "%g in", item.lengthIn))
                            .font(.headline.monospacedDigit())
                    }
                }
                Stepper(value: $item.depthFt, in: 0...300, step: 1) {
                    HStack {
                        Text("Depth")
                        Spacer()
                        Text(String(format: "%g ft", item.depthFt))
                            .font(.headline.monospacedDigit())
                    }
                }
                HStack {
                    Text("Water temp")
                    Spacer()
                    TextField("°F", text: $waterTempText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
            }

            Section("Gear") {
                TextField("Lure color 1", text: $item.lureColor1)
                    .textInputAutocapitalization(.words)
            }

            Section("Time") {
                DatePicker("Caught at",
                           selection: $item.timestamp,
                           displayedComponents: [.date, .hourAndMinute])
            }
        }
        .navigationTitle("Edit Catch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .font(.headline)
            }
        }
        .onAppear(perform: seed)
    }

    private func seed() {
        guard !didSeed else { return }
        didSeed = true
        if let t = item.waterTempF {
            waterTempText = String(format: "%g", t)
        }
    }

    private func save() {
        let trimmed = waterTempText.trimmingCharacters(in: .whitespaces)
        item.waterTempF = trimmed.isEmpty ? nil : Double(trimmed)
        item.species = item.species.trimmingCharacters(in: .whitespaces).lowercased()
        store.updateCatch(item)
        dismiss()
    }
}
