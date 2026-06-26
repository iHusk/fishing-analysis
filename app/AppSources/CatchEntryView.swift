import SwiftUI
import CoreLocation
import UIKit

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

    // Water temp + per-catch weight live behind disclosures (collapsed by default).
    @State private var waterTempOn = false
    @State private var waterTempF: Double = 64
    @State private var tempExpanded = false

    @State private var weightOn = false
    @State private var weightLbsValue: Double = 2.0
    @State private var weightExpanded = false

    // Lure disclosure: color 2 only appears once the angler asks for it.
    @State private var showColor2 = false

    @State private var didSeed = false

    /// GPS fix captured at open and held for the lifetime of this entry.
    @State private var taggedFix: CLLocation?

    // Lightweight "add new" prompt, shared by angler / species / lure color.
    private enum AddTarget { case fisherman, species, lure1, lure2 }
    @State private var addTarget: AddTarget?
    @State private var newOptionText = ""

    // Bait radial (hoisted to a full-screen overlay) + swipe-to-log screen tint.
    @StateObject private var baitRadial = BaitRadialController()
    @State private var swipeSignal: Double = 0   // -1 = releasing(red) … +1 = keeping(green)

    var body: some View {
        VStack(spacing: 14) {
            topBar
            anglerRow
            speciesRow

            measures

            lureRow
            RadialBaitPicker(selection: $bait, controller: baitRadial)
            secondaryRow

            Spacer(minLength: 4)

            SwipeToLogBar(
                signal: $swipeSignal,
                onKeep: { commit(kept: true) },
                onRelease: { commit(kept: false) }
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 14)
        // VStack respects the top safe area (clears the notch/status bar); the
        // background paints behind it, under the notch.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(FishTheme.bg.ignoresSafeArea())
        .overlay { swipeTint }
        .overlay { BaitRadialOverlay(controller: baitRadial).ignoresSafeArea() }
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

    /// Subtle full-screen edge tint while swiping the log bar: green = keeping, red = releasing.
    private var swipeTint: some View {
        let p = min(1, abs(swipeSignal))
        let color = swipeSignal >= 0 ? Color(hex: 0x34C759) : Color(hex: 0xFF453A)
        return RadialGradient(colors: [.clear, color.opacity(0.26 * p)],
                              center: .center, startRadius: 170, endRadius: 540)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .opacity(p > 0.02 ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: swipeSignal)
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
            // Length is the hero — big readout, tall tape.
            tapeCard(title: "LENGTH") {
                TapeInput(value: $lengthIn, range: 0...60, step: 0.25, unit: "in",
                          majorEvery: 4, readoutSize: 56, tapeHeight: 92)
            }
            // Depth is the supporting value — compact readout, shorter tape.
            tapeCard(title: "DEPTH") {
                TapeInput(value: $depthFt, range: 0...300, step: 0.5, unit: "ft",
                          majorEvery: 2, readoutSize: 30, tapeHeight: 54)
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
                // The ＋ IS the color-2 picker: one tap opens the menu directly.
                colorMenu(isColor2: true) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FishTheme.inkDim)
                        .frame(width: 36, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(FishTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                }
            }
            Spacer()
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .fishPanel()
    }

    /// A Menu of known lure colors that writes to color 1 or color 2, wrapping any label.
    private func colorMenu<L: View>(isColor2: Bool, @ViewBuilder _ label: () -> L) -> some View {
        Menu {
            Button("— none —") {
                if isColor2 { lure2 = "" } else { lure1 = "" }
            }
            ForEach(store.knownLureColors, id: \.self) { c in
                Button { isColor2 ? (lure2 = c) : (lure1 = c); if isColor2 { showColor2 = true } } label: {
                    if let s = lureSwatch(c) {
                        // Menus ignore SF-symbol foreground colors, so render a real
                        // colored-circle image (kept in .original rendering mode).
                        Label { Text(c) } icon: { swatchImage(s) }
                    } else {
                        Text(c)
                    }
                }
            }
            Divider()
            Button("Add new…", systemImage: "plus") { addTarget = isColor2 ? .lure2 : .lure1 }
        } label: { label() }
    }

    private func colorSlot(value: String, isColor2: Bool) -> some View {
        colorMenu(isColor2: isColor2) {
            HStack(spacing: 7) {
                if let swatch = lureSwatch(value) {
                    Circle().fill(swatch)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(FishTheme.line, lineWidth: 1))
                }
                Text(value.isEmpty ? "Color \(isColor2 ? 2 : 1)" : value)
                    .font(FishTheme.display(15, .semibold))
                    .foregroundStyle(value.isEmpty ? FishTheme.inkFaint : FishTheme.ink)
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(FishTheme.panelHi))
            .overlay(Capsule().strokeBorder(FishTheme.line, lineWidth: 1))
        }
    }

    /// A small filled-circle image in the given color, rendered in `.original` mode so
    /// it keeps its color inside a SwiftUI `Menu` (which tints template symbols).
    private func swatchImage(_ color: Color) -> Image {
        let size = CGSize(width: 14, height: 14)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(color).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        return Image(uiImage: img.withRenderingMode(.alwaysOriginal))
    }

    /// Representative swatch color for a known lure-color name (nil → no pip).
    private func lureSwatch(_ name: String) -> Color? {
        switch name.lowercased() {
        case "bare", "white":   return Color(hex: 0xF2F2F2)
        case "red hooks", "red": return Color(hex: 0xE5453B)
        case "chartreuse":      return Color(hex: 0xCDEB1E)
        case "firetiger":       return Color(hex: 0xE8A317)
        case "gold":            return Color(hex: 0xE7B53B)
        case "silver":          return Color(hex: 0xC7CCD1)
        case "purple":          return Color(hex: 0x8A4FC4)
        case "pink":            return Color(hex: 0xF06FA8)
        case "orange":          return Color(hex: 0xF07F22)
        case "glow":            return Color(hex: 0xD7F0A8)
        case "black":           return Color(hex: 0x2A2E35)
        case "blue":            return Color(hex: 0x3E7FD6)
        case "green":           return Color(hex: 0x3FA85B)
        case "perch":           return Color(hex: 0x7E8A3A)
        case "clown":           return Color(hex: 0xEF6A3D)
        default:                return nil
        }
    }

    // MARK: - Water temp (disclosure)

    /// Water temp + per-catch weight, two compact disclosure pills sharing one panel.
    /// Only one expands at a time (inline slider) so the screen never scrolls.
    private var secondaryRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                discPill(title: "WATER TEMP",
                         value: waterTempOn ? "\(Int(waterTempF))°" : "—",
                         expanded: tempExpanded) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        tempExpanded.toggle()
                        if tempExpanded { waterTempOn = true; weightExpanded = false }
                    }
                }
                discPill(title: "WEIGHT",
                         value: weightOn ? String(format: "%.1f lb", weightLbsValue) : "—",
                         expanded: weightExpanded) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        weightExpanded.toggle()
                        if weightExpanded { weightOn = true; tempExpanded = false }
                    }
                }
            }
            if tempExpanded {
                compactTape(value: $waterTempF, range: 32...90, step: 1, unit: "°", majorEvery: 5) {
                    waterTempOn = false; tempExpanded = false
                }
            }
            if weightExpanded {
                compactTape(value: $weightLbsValue, range: 0...15, step: 0.1, unit: "lb", majorEvery: 10) {
                    weightOn = false; weightExpanded = false
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fishPanel()
    }

    private func discPill(title: String, value: String, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).fishEyebrow()
                Spacer(minLength: 4)
                Text(value)
                    .font(FishTheme.display(15, .semibold))
                    .foregroundStyle(value == "—" ? FishTheme.inkFaint : FishTheme.ink)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FishTheme.inkFaint)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(FishTheme.panelHi))
            .overlay(Capsule().strokeBorder(expanded ? FishTheme.accent.opacity(0.5) : FishTheme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// A small momentum tape (same control as Length/Depth, sized down) shown inline
    /// when a disclosure pill is tapped, plus a Clear button.
    private func compactTape(value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                             unit: String, majorEvery: Int, clear: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            TapeInput(value: value, range: range, step: step, unit: unit,
                      majorEvery: majorEvery, readoutSize: 24, tapeHeight: 46)
            Button(action: clear) {
                Text("Clear").font(FishTheme.mono(11, .medium)).foregroundStyle(FishTheme.inkDim)
            }
            .buttonStyle(.plain)
        }
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
            measuredWtLbs: weightOn ? weightLbsValue : nil,
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
    @Binding var signal: Double
    var onKeep: () -> Void
    var onRelease: () -> Void

    @State private var dragX: CGFloat = 0
    @State private var committing = false

    private let height: CGFloat = 70
    private let thumbW: CGFloat = 138
    private let thumbH: CGFloat = 56
    private let keepColor = Color(hex: 0x34C759)
    private let releaseColor = Color(hex: 0xFF453A)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let maxOffset = max(40, (w - thumbW) / 2 - 6)
            let threshold = max(56, maxOffset * 0.72)
            let progress = min(1, abs(dragX) / threshold)
            let goingRight = dragX >= 0
            let active = progress > 0.12
            let dirColor = goingRight ? keepColor : releaseColor

            ZStack {
                Capsule().fill(FishTheme.panel)
                Capsule().strokeBorder(FishTheme.line, lineWidth: 1)
                Capsule().fill(dirColor.opacity(0.30 * progress))   // neutral at rest

                // Faint directional arrows only — no edge text for the thumb to cover.
                HStack {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(active && !goingRight ? releaseColor : FishTheme.inkFaint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(active && goingRight ? keepColor : FishTheme.inkFaint)
                }
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 22)

                thumb(active: active, goingRight: goingRight, color: dirColor)
                    .offset(x: max(-maxOffset, min(maxOffset, dragX)))
            }
            .frame(height: height)
            .contentShape(Capsule())
            .gesture(
                DragGesture()
                    .onChanged { g in
                        guard !committing else { return }
                        let x = max(-maxOffset, min(maxOffset, g.translation.width))
                        dragX = x
                        signal = Double(x / maxOffset)
                    }
                    .onEnded { _ in
                        if abs(dragX) >= threshold {
                            committing = true
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            let right = dragX >= 0
                            withAnimation(.easeOut(duration: 0.18)) {
                                dragX = right ? maxOffset : -maxOffset
                                signal = right ? 1 : -1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                                right ? onKeep() : onRelease()
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                dragX = 0; signal = 0
                            }
                        }
                    }
            )
        }
        .frame(height: height)
    }

    private func thumb(active: Bool, goingRight: Bool, color: Color) -> some View {
        let text = !active ? "SWIPE" : (goingRight ? "KEEP" : "RELEASE")
        let icon = !active ? "chevron.left.chevron.right" : (goingRight ? "checkmark" : "arrow.uturn.left")
        return HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
            Text(text).font(FishTheme.mono(13, .semibold)).tracking(1.5)
        }
        .foregroundStyle(active ? .white : FishTheme.ink)
        .frame(width: thumbW, height: thumbH)
        .background(
            Capsule().fill(
                active
                ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.92), color],
                                               startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(LinearGradient(colors: [FishTheme.panelHi, FishTheme.panel],
                                               startPoint: .top, endPoint: .bottom))
            )
        )
        .overlay(Capsule().strokeBorder(active ? .clear : FishTheme.line, lineWidth: 1.5))
        .shadow(color: active ? color.opacity(0.55) : .black.opacity(0.4),
                radius: active ? 16 : 8, y: 3)
    }
}
