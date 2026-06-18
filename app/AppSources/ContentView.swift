import SwiftUI
import UIKit
import CoreLocation

/// On-water "Now" screen. The thumb-reachable bottom third holds the primary
/// LOG CATCH action; the top carries the trust UX (today's count, active
/// session, GPS status) and the Undo-last affordance.
struct ContentView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var loc: LocationManager

    @State private var showCatchEntry = false
    @State private var showDayLog = false
    @State private var showWeighIn = false
    @State private var showShare = false

    /// The most recently saved catch, kept so the user can Undo immediately
    /// after a save without hunting through the day log.
    @State private var lastSaved: FishCatch?
    @State private var showUndoToast = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    statusHeader
                    Spacer(minLength: 8)
                    secondaryActions
                    Spacer(minLength: 8)
                    logButton
                }
                .padding()

                if showUndoToast, let saved = lastSaved {
                    undoToast(for: saved)
                        .padding(.bottom, 130)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Fishing Logger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            // Catch entry
            .sheet(isPresented: $showCatchEntry) {
                CatchEntryView { newCatch in
                    handleSaved(newCatch)
                }
                .environmentObject(store)
                .environmentObject(loc)
            }
            // Day log
            .sheet(isPresented: $showDayLog) {
                NavigationStack {
                    DayLogView()
                        .environmentObject(store)
                        .navigationTitle("Today's Catches")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showDayLog = false }
                            }
                        }
                }
            }
            // Weigh-in
            .sheet(isPresented: $showWeighIn) {
                NavigationStack {
                    WeighInView()
                        .environmentObject(store)
                        .navigationTitle("Daily Weigh-In")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Cancel") { showWeighIn = false }
                            }
                        }
                }
            }
            // Export
            .sheet(isPresented: $showShare) {
                ShareSheet(items: store.exportURLs)
            }
        }
    }

    // MARK: - Header (trust UX)

    private var statusHeader: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fish logged today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(store.todaysCatches.count)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(store.activeSessionID.isEmpty ? "—" : store.activeSessionID)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(store.activeTrip.isEmpty ? "" : "Trip \(store.activeTrip)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            gpsStatusLine
            if loc.isRecording == false {
                EmptyView()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var gpsStatusLine: some View {
        HStack(spacing: 8) {
            Image(systemName: gpsSymbol)
                .foregroundStyle(gpsColor)
            Text(gpsText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if loc.isRecording {
                Label("TRACK ON", systemImage: "record.circle")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
    }

    private var gpsSymbol: String {
        guard loc.authorized else { return "location.slash" }
        return loc.current == nil ? "location" : "location.fill"
    }

    private var gpsColor: Color {
        guard loc.authorized else { return .orange }
        return loc.current == nil ? .secondary : .green
    }

    private var gpsText: String {
        guard loc.authorized else { return "Location not authorized" }
        guard let c = loc.current else { return "Acquiring GPS…" }
        return String(format: "GPS ±%.0f m", max(c.horizontalAccuracy, 0))
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                actionTile("Day Log", systemImage: "list.bullet.rectangle") {
                    showDayLog = true
                }
                actionTile("Weigh-In", systemImage: "scalemass") {
                    showWeighIn = true
                }
            }
            HStack(spacing: 12) {
                if loc.isRecording {
                    actionTile("Stop Track", systemImage: "stop.circle", tint: .red) {
                        loc.stopRecording()
                    }
                } else {
                    actionTile("Start Track", systemImage: "play.circle", tint: .blue) {
                        loc.startRecording()
                    }
                }
                actionTile("Export", systemImage: "square.and.arrow.up") {
                    showShare = true
                }
            }
        }
    }

    private func actionTile(
        _ title: String,
        systemImage: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 70)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    // MARK: - Primary LOG button

    private var logButton: some View {
        Button {
            showCatchEntry = true
        } label: {
            Label("LOG CATCH", systemImage: "fish.fill")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 96)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
    }

    // MARK: - Undo

    private func undoToast(for saved: FishCatch) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved \(saved.fisherman.isEmpty ? saved.species : saved.fisherman)'s fish")
                    .font(.subheadline.bold())
                Text(String(format: "%g in · %g ft", saved.lengthIn, saved.depthFt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                undoLast()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .shadow(radius: 6, y: 2)
        )
        .padding(.horizontal)
    }

    private func handleSaved(_ newCatch: FishCatch) {
        lastSaved = newCatch
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        withAnimation { showUndoToast = true }
        // Auto-hide the toast after a few seconds; the catch remains in the day log.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            withAnimation {
                if lastSaved?.uuid == newCatch.uuid {
                    showUndoToast = false
                }
            }
        }
    }

    private func undoLast() {
        guard let saved = lastSaved else { return }
        store.deleteCatch(saved)
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        withAnimation {
            showUndoToast = false
            lastSaved = nil
        }
    }
}
