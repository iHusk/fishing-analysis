import SwiftUI
import CoreLocation

/// The "Tape Wheel" catch-entry screen (ADR 0006 / HAY-133).
///
/// A pre-filled "confirm + adjust" instrument: open → glance → nudge length →
/// swipe to log. Every field is seeded from the selected angler's remembered
/// defaults (falling back to the store's global carry-forward), and the GPS fix
/// is frozen the instant the screen opens so the saved point can't drift.
///
/// Data plumbing (seed / frozen GPS / `store.addCatch`) is unchanged from the
/// previous Form-based screen — only the *presentation* is the Tape Wheel.
struct CatchEntryView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var loc: LocationManager
    @EnvironmentObject private var profiles: AnglerProfileStore
    @Environment(\.dismiss) private var dismiss

    /// Called with the freshly persisted catch so the caller can offer Undo.
    let onSaved: (FishCatch) -> Void

    // Local editable state, seeded from defaults on appear.
    @State private var fisherman = ""
    @State private var species = "walleye"
    @State private var lengthIn: Double = 15.0
    @State private var depthFt: Double = 20.0
    @State private var lure1 = ""
    @State private var lure2 = ""
    @State private var bait = "Crawler"
    @State private var locationName = ""

    // Water temp lives behind a disclosure (collapsed by default).
    @State private var waterTempOn = false
    @State private var waterTempF: Double = 64
    @State private var tempExpanded = false

    // Lure disclosure: color 2 only appears once the angler asks for it.
    @State private var showColor2 = false

    @State private var didSeed = false

    /// GPS fix captured at open and held for the lifetime of this entry.
    @State private var taggedFix: CLLocation?

    // Lightweight "add new" prompt, shared by angler / species / lure color.
    private enum AddTarget { case fisherman, species, lure1, lure2 }
    @State private var addTarget: AddTarget?
    @State private var newOptionText = ""

    var body: some View {
        ZStack {
            FishTheme.bg.ignoresSafeArea()

            VStack(spacing: 14) {
                topBar
                anglerRow
                speciesRow

                measures

                lureRow
                RadialBaitPicker(selection: $bait)
                waterTempRow

                Spacer(minLength: 4)

                SwipeToLogBar(
                    onKeep: { commit(kept: true) },
                    onRelease: { commit(kept: false) }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: seedOnce)
        .alert("Add new", isPresented: Binding(
            get: { addTarget != nil },
            set: { if !$0 { addTarget = nil; newOptionText = "" } }
        )) {
            TextField("Name", text: $newOptionText)
            Button("Add") { commitNewOption() }
            Button("Cancel", role: .cancel) { addTarget = nil; newOptionText = "" }
        }
    }

    // MARK: - Top bar (close + spot)

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(FishTheme.inkDim)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(FishTheme.panel))
                    .overlay(Circle().strokeBorder(FishTheme.line, lineWidth: 1))
            }

            Spacer()

            // Spot pill. Auto-naming (HAY-130) isn't built yet, so this is the
            // free-text / carry-forward location, tappable to edit.
            Menu {
                if !store.lastLocationName.isEmpty {
                    Button(store.lastLocationName) { locationName = store.lastLocationName }
                }
                Button("Clear") { locationName = "" }
                Button("Type a spot…") { addTarget = nil /* keep simple: edit via field below */ }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: taggedFix == nil ? "location.slash" : "location.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(locationName.isEmpty ? "Add spot" : locationName)
                        .font(FishTheme.mono(12, .medium))
                }
                .foregroundStyle(FishTheme.cyan)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(FishTheme.cyan.opacity(0.12)))
                .overlay(Capsule().strokeBorder(FishTheme.cyan.opacity(0.3), lineWidth: 1))
            }
        }
    }

    // MARK: - Angler

    private var anglerRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.knownFishermen, id: \.self) { name in
                    chip(name, selected: fisherman == name) { selectAngler(name) }
                }
                chip("＋", selected: false) { addTarget = .fisherman }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(FishTheme.display(15, selected ? .bold : .medium))
                .foregroundStyle(selected ? FishTheme.accentInk : FishTheme.inkDim)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(
                    Capsule().fill(
                        selected
                        ? AnyShapeStyle(LinearGradient(colors: [FishTheme.accent2, FishTheme.accent],
                                                       startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(FishTheme.panel)
                    )
                )
                .overlay(Capsule().strokeBorder(selected ? .clear : FishTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Species

    private var speciesRow: some View {
        Menu {
            ForEach(store.knownSpecies, id: \.self) { s in
                Button(s.capitalized) { species = s.lowercased() }
            }
            Divider()
            Button("Add new…", systemImage: "plus") { addTarget = .species }
        } label: {
            HStack(spacing: 10) {
                Text(species.capitalized)
                    .font(FishTheme.display(28, .bold))
                    .foregroundStyle(FishTheme.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FishTheme.inkFaint)
                Spacer()
            }
        }
    }

    // MARK: - Measurements (the twin tapes)

    private var measures: some View {
        VStack(spacing: 10) {
            tapeCard(title: "LENGTH") {
                TapeInput(value: $lengthIn, range: 0...60, step: 0.25, unit: "in", majorEvery: 4)
            }
            tapeCard(title: "DEPTH") {
                TapeInput(value: $depthFt, range: 0...300, step: 0.5, unit: "ft", majorEvery: 2)
            }
        }
    }

    private func tapeCard<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).fishEyebrow().padding(.leading, 4)
            content()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .fishPanel()
    }

    // MARK: - Lure colors (progressive: Color 1, then ＋ reveals Color 2)

    private var lureRow: some View {
        HStack(spacing: 10) {
            Text("LURE").fishEyebrow()
            colorSlot(value: lure1, isColor2: false)
            if showColor2 || !lure2.isEmpty {
                colorSlot(value: lure2, isColor2: true)
            } else {
                Button { showColor2 = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FishTheme.inkDim)
                        .frame(width: 36, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(FishTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .fishPanel()
    }

    private func colorSlot(value: String, isColor2: Bool) -> some View {
        Menu {
            Button("— none —") { isColor2 ? (lure2 = "") : (lure1 = "") }
            ForEach(store.knownLureColors, id: \.self) { c in
                Button(c) { isColor2 ? (lure2 = c) : (lure1 = c) }
            }
            Divider()
            Button("Add new…", systemImage: "plus") { addTarget = isColor2 ? .lure2 : .lure1 }
        } label: {
            Text(value.isEmpty ? "Color \(isColor2 ? 2 : 1)" : value)
                .font(FishTheme.display(15, .semibold))
                .foregroundStyle(value.isEmpty ? FishTheme.inkFaint : FishTheme.ink)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(FishTheme.panelHi))
                .overlay(Capsule().strokeBorder(FishTheme.line, lineWidth: 1))
        }
    }

    // MARK: - Water temp (disclosure)

    private var waterTempRow: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    tempExpanded.toggle()
                    if tempExpanded { waterTempOn = true }
                }
            } label: {
                HStack {
                    Text("WATER TEMP").fishEyebrow()
                    Spacer()
                    Text(waterTempOn ? "\(Int(waterTempF))°" : "—")
                        .font(FishTheme.display(16, .semibold))
                        .foregroundStyle(waterTempOn ? FishTheme.ink : FishTheme.inkFaint)
                    Image(systemName: tempExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FishTheme.inkFaint)
                }
            }
            .buttonStyle(.plain)

            if tempExpanded {
                HStack(spacing: 12) {
                    Slider(value: $waterTempF, in: 32...90, step: 1)
                        .tint(FishTheme.accent)
                    Button {
                        waterTempOn = false; tempExpanded = false
                    } label: {
                        Text("Clear").font(FishTheme.mono(11, .medium)).foregroundStyle(FishTheme.inkDim)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fishPanel()
    }

    // MARK: - Seed + Save

    private func seedOnce() {
        guard !didSeed else { return }
        didSeed = true
        taggedFix = loc.current

        fisherman = store.lastFisherman
        // Prefer the selected angler's remembered profile; else global carry-forward.
        if let p = profiles.profile(for: fisherman) {
            applyProfile(p)
        } else {
            lengthIn = store.lastLength > 0 ? store.lastLength : 15.0
            depthFt = store.lastDepth > 0 ? store.lastDepth : 20.0
            lure1 = store.lastLure1
            lure2 = store.lastLure2
            bait = store.lastBait.isEmpty ? "Crawler" : store.lastBait
            locationName = store.lastLocationName
            if let t = store.lastWaterTemp { waterTempF = t; waterTempOn = true }
        }
        if !lure2.isEmpty { showColor2 = true }
    }

    private func selectAngler(_ name: String) {
        fisherman = name
        if let p = profiles.profile(for: name) {
            withAnimation(.easeOut(duration: 0.2)) { applyProfile(p) }
        }
    }

    private func applyProfile(_ p: AnglerProfile) {
        species = p.species.isEmpty ? species : p.species
        lengthIn = p.lengthIn > 0 ? p.lengthIn : lengthIn
        depthFt = p.depthFt > 0 ? p.depthFt : depthFt
        lure1 = p.lure1
        lure2 = p.lure2
        bait = p.bait.isEmpty ? "Crawler" : p.bait
        locationName = p.locationName
        if let t = p.waterTempF { waterTempF = t; waterTempOn = true }
        if !p.lure2.isEmpty { showColor2 = true }
    }

    private func commitNewOption() {
        let v = newOptionText.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty, let target = addTarget {
            switch target {
            case .fisherman: fisherman = v
            case .species:   species = v.lowercased(); store.noteSpecies(species)
            case .lure1:     lure1 = v; store.noteLureColor(v)
            case .lure2:     lure2 = v; store.noteLureColor(v)
            }
        }
        newOptionText = ""
        addTarget = nil
    }

    private func commit(kept: Bool) {
        let waterTemp: Double? = waterTempOn ? waterTempF : nil
        let speciesValue = species.trimmingCharacters(in: .whitespaces).lowercased()

        let newCatch = store.addCatch(
            fisherman: fisherman.trimmingCharacters(in: .whitespaces),
            species: speciesValue.isEmpty ? "walleye" : speciesValue,
            kept: kept,
            lengthIn: lengthIn,
            depthFt: depthFt,
            waterTempF: waterTemp,
            lure1: lure1.trimmingCharacters(in: .whitespaces),
            lure2: lure2.trimmingCharacters(in: .whitespaces),
            bait: bait.trimmingCharacters(in: .whitespaces),
            locationName: locationName.trimmingCharacters(in: .whitespaces),
            loc: taggedFix
        )
        profiles.remember(from: newCatch)
        onSaved(newCatch)
        dismiss()
    }
}

#if DEBUG
#Preview {
    let store = Store()
    store.knownFishermen = ["Tyler", "Brian", "Brent"]
    store.lastFisherman = "Tyler"
    store.lastLength = 18.5
    store.lastDepth = 22
    store.lastLure1 = "Firetiger"
    store.lastBait = "Crawler"
    store.lastLocationName = "North Flat"
    return CatchEntryView { _ in }
        .environmentObject(store)
        .environmentObject(LocationManager())
        .environmentObject(AnglerProfileStore())
}
#endif

// MARK: - Swipe-to-log bar

/// Disposition folded into Save: drag RIGHT past the threshold to **Keep & Log**,
/// LEFT to **Release & Log**. Releasing before the threshold springs back.
private struct SwipeToLogBar: View {
    var onKeep: () -> Void
    var onRelease: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var committing = false

    private let height: CGFloat = 66

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let threshold = w * 0.32
            let progress = min(1, abs(dragX) / threshold)
            let goingRight = dragX >= 0

            ZStack {
                // Track + directional intent fill.
                Capsule().fill(FishTheme.panel)
                Capsule().strokeBorder(FishTheme.line, lineWidth: 1)
                Capsule()
                    .fill((goingRight ? FishTheme.accent : FishTheme.cyan).opacity(0.18 + 0.22 * progress))

                // Edge labels.
                HStack {
                    label("RELEASE", icon: "arrow.uturn.left", color: FishTheme.cyan,
                          active: !goingRight && progress > 0.1)
                    Spacer()
                    label("KEEP", icon: "checkmark", color: FishTheme.accent,
                          active: goingRight && progress > 0.1)
                }
                .padding(.horizontal, 22)

                // Center hint + thumb.
                Text(progress > 0.1
                     ? (goingRight ? "KEEP & LOG" : "RELEASE & LOG")
                     : "SWIPE TO LOG")
                    .font(FishTheme.mono(12, .medium))
                    .tracking(1.5)
                    .foregroundStyle(FishTheme.inkDim)

                thumb(goingRight: goingRight, progress: progress)
                    .offset(x: dragX)
            }
            .frame(height: height)
            .contentShape(Capsule())
            .gesture(
                DragGesture()
                    .onChanged { g in
                        guard !committing else { return }
                        // Clamp so the thumb stays within the track.
                        dragX = max(-w/2 + 33, min(w/2 - 33, g.translation.width))
                    }
                    .onEnded { _ in
                        if abs(dragX) >= threshold {
                            committing = true
                            #if canImport(UIKit)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            #endif
                            let right = dragX >= 0
                            withAnimation(.easeOut(duration: 0.18)) {
                                dragX = right ? (w/2 - 33) : -(w/2 - 33)
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                right ? onKeep() : onRelease()
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragX = 0 }
                        }
                    }
            )
        }
        .frame(height: height)
    }

    private func label(_ text: String, icon: String, color: Color, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
            Text(text).font(FishTheme.mono(11, .medium)).tracking(1)
        }
        .foregroundStyle(active ? color : FishTheme.inkFaint)
    }

    private func thumb(goingRight: Bool, progress: CGFloat) -> some View {
        let color = goingRight ? FishTheme.accent : FishTheme.cyan
        return ZStack {
            Circle().fill(
                LinearGradient(colors: [color, color.opacity(0.8)],
                               startPoint: .top, endPoint: .bottom)
            )
            Image(systemName: progress > 0.1 ? (goingRight ? "checkmark" : "arrow.uturn.left")
                                             : "chevron.left.chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(goingRight ? FishTheme.accentInk : FishTheme.bg)
        }
        .frame(width: 56, height: 56)
        .shadow(color: color.opacity(0.5), radius: progress > 0.1 ? 14 : 6)
    }
}
