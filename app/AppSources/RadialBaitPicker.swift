//
//  RadialBaitPicker.swift
//  FishingLogger
//
//  Press-and-hold radial bait selector.
//  Ported from wireframes/claude/bait-picker-radial.html — dark "instrument"
//  aesthetic, single amber accent, Sora display + DM Mono labels (via FishTheme).
//
//  Interaction:
//    RESTING  — a quiet row: eyebrow "BAIT" + current value, with a subtle
//               breathing amber "hold" affordance. Press/hold IS the interaction.
//    ARM      — after ~0.32s of holding, a dimming scrim covers the screen and a
//               radial blooms FROM the press point: four ~92pt glove-friendly
//               petals at the cardinal directions (Minnow=up, Lure=right,
//               Jig=down, Crawler=left for the default 4 options).
//    DRAG     — pick the dominant axis past a ~34pt dead zone, highlight exactly
//               one petal in solid amber, scaled up + glow, with a needle from
//               center. Center hub shows current value + "Release to cancel".
//               Dragging back into the dead zone clears the selection.
//    RELEASE  — commit the highlighted option to the binding (release on center
//               cancels and keeps current). Flash an amber confirmation ring.
//
//  Haptics: light impact on bloom, selection feedback on highlight change,
//           success notification on commit.
//
//  Self-contained. Presents the radial + scrim as a ZStack overlay (drawn in a
//  full-screen overlay) so it can draw over the rest of the screen.
//

import SwiftUI
import UIKit

// MARK: - Public API

struct RadialBaitPicker: View {

    @Binding private var selection: String
    private let options: [String]
    private let onAddNew: (() -> Void)?

    init(selection: Binding<String>,
         options: [String] = ["Crawler", "Minnow", "Lure", "Jig"],
         onAddNew: (() -> Void)? = nil) {
        self._selection = selection
        self.options = options
        self.onAddNew = onAddNew
    }

    var body: some View {
        RestingRow(selection: $selection, options: options, onAddNew: onAddNew)
    }
}

// MARK: - Resting row (the whole interaction lives here)

private struct RestingRow: View {

    @Binding var selection: String
    let options: [String]
    let onAddNew: (() -> Void)?

    // press / arm state
    @State private var pressing = false          // finger is down
    @State private var armed = false             // radial open & tracking
    @State private var pressProgress: CGFloat = 0 // 0..1 fill while arming
    @State private var holdWorkItem: DispatchWorkItem?

    // geometry captured at press time (global coords)
    @State private var pressPoint: CGPoint = .zero
    @State private var dragPoint: CGPoint = .zero

    // current highlighted bait (nil == center / cancel)
    @State private var hovered: String?

    // breathing affordance + commit confirmation
    @State private var breathe = false
    @State private var committedFlash = false

    // haptics
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let success = UINotificationFeedbackGenerator()

    private let holdSeconds: Double = 0.32
    private let deadZone: CGFloat = 34

    var body: some View {
        restingContent
            // capture the press location in GLOBAL space so the bloom can be
            // positioned anywhere on screen via the overlay.
            .background(
                GeometryReader { _ in Color.clear }
            )
            // Full-screen radial overlay — drawn above everything in the window.
            .overlay {
                if armed {
                    radialOverlay
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            // minimumDistance 0 → fires immediately on touch-down; we arm via a
            // timer and then treat subsequent movement as the directional flick.
            .gesture(pressDragGesture)
            .onAppear {
                impact.prepare()
                selectionHaptic.prepare()
                success.prepare()
                breathe = true
            }
    }

    // MARK: Resting visual

    private var restingContent: some View {
        ZStack {
            // press-progress fill sweeps up from the bottom while arming
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [FishTheme.panelHi, FishTheme.panel],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    LinearGradient(
                        colors: [.clear, FishTheme.accent.opacity(0.16)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: geo.size.height * pressProgress)
                    .allowsHitTesting(false)
                }
            }

            HStack(spacing: 14) {
                // bait glyph chip
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(FishTheme.accent.opacity(0.12))
                    BaitGlyph(name: selection)
                        .stroke(FishTheme.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .padding(9)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    eyebrow("BAIT")
                    Text(selection)
                        .font(FishTheme.display(24, .bold))
                        .foregroundColor(FishTheme.ink)
                }

                Spacer(minLength: 8)

                // breathing "Hold" affordance
                HStack(spacing: 7) {
                    Circle()
                        .fill(FishTheme.accent)
                        .frame(width: 9, height: 9)
                        .shadow(color: FishTheme.accentGlow, radius: 5)
                        .scaleEffect(breathe ? 1.0 : 0.85)
                        .opacity(breathe ? 1.0 : 0.35)
                        .animation(
                            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                            value: breathe
                        )
                    Text("HOLD")
                        .font(FishTheme.mono(9, .medium))
                        .tracking(0.8)
                        .foregroundColor(FishTheme.inkFaint)
                }

                // optional tiny "+" to reach a free-text add — secondary to the
                // flick. Kept out of the press gesture's way via .highPriority.
                if let onAddNew {
                    Button(action: onAddNew) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(FishTheme.inkDim)
                            .frame(width: 28, height: 28)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(FishTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add new bait")
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 74)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    committedFlash ? FishTheme.accent : (armed ? FishTheme.accent.opacity(0.7) : FishTheme.line),
                    lineWidth: committedFlash ? 1.6 : 1
                )
                .shadow(color: committedFlash ? FishTheme.accentGlow : .clear, radius: committedFlash ? 10 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: committedFlash)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // small eyebrow — uses the shared `.fishEyebrow()` helper if present, with a
    // local style applied so it still reads correctly.
    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(FishTheme.mono(9, .medium))
            .tracking(2.0)
            .foregroundColor(FishTheme.inkFaint)
            .fishEyebrow()
    }

    // MARK: Radial overlay (scrim + bloom), positioned at the press point

    private var radialOverlay: some View {
        GeometryReader { geo in
            ZStack {
                // dimming spotlight scrim, brighter near the touch point
                RadialGradient(
                    colors: [
                        Color(hex: 0x08_0A_0D, alpha: 0.34),
                        Color(hex: 0x08_0A_0D, alpha: 0.82)
                    ],
                    center: UnitPoint(
                        x: pressPoint.x / max(geo.size.width, 1),
                        y: pressPoint.y / max(geo.size.height, 1)
                    ),
                    startRadius: 0,
                    endRadius: 420
                )
                .ignoresSafeArea()

                bloom
                    .position(pressPoint)
            }
        }
        // The gesture lives on the resting row; this overlay is purely visual and
        // must NOT intercept touches, or the in-flight drag would be cancelled.
        .allowsHitTesting(false)
    }

    private var bloom: some View {
        ZStack {
            // needle from center toward the active petal
            if let dir = activeDirection {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [FishTheme.accentGlow, .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 92, height: 2)
                    // anchor the left end at center, rotate outward
                    .offset(x: 46)
                    .rotationEffect(dir.angle)
                    .transition(.opacity)
            }

            // four petals at cardinal positions
            ForEach(layout, id: \.bait) { item in
                petal(item)
                    .position(petalPosition(item, hot: hovered == item.bait))
                    .animation(.spring(response: 0.2, dampingFraction: 0.8),
                               value: hovered == item.bait)
            }

            // center hub == cancel target
            hub
        }
        .frame(width: 280, height: 280)
    }

    // MARK: Hub

    private var hub: some View {
        let cancel = hovered == nil
        return VStack(spacing: 2) {
            Text("RELEASE TO\nCANCEL")
                .font(FishTheme.mono(8, .regular))
                .tracking(0.9)
                .multilineTextAlignment(.center)
                .foregroundColor(FishTheme.inkFaint)
            Text(selection)
                .font(FishTheme.display(13, .bold))
                .foregroundColor(FishTheme.ink)
        }
        .frame(width: 74, height: 74)
        .background(
            Circle().fill(
                RadialGradient(
                    colors: [FishTheme.panelHi, Color(hex: 0x0C_0F_13, alpha: 1)],
                    center: UnitPoint(x: 0.5, y: 0.38),
                    startRadius: 0, endRadius: 40
                )
            )
        )
        .overlay(
            Circle().strokeBorder(cancel ? FishTheme.inkDim : FishTheme.line, lineWidth: 1.5)
        )
        .overlay(
            Circle()
                .stroke(FishTheme.inkDim.opacity(cancel ? 0.4 : 0), lineWidth: 4)
        )
        .scaleEffect(cancel ? 1.04 : 1.0)
        .shadow(color: .black.opacity(0.6), radius: 14, y: 10)
        .animation(.easeOut(duration: 0.1), value: cancel)
    }

    // MARK: Petal

    private func petal(_ item: LayoutItem) -> some View {
        let hot = hovered == item.bait
        let isCurrent = item.bait == selection
        return ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    hot
                    ? AnyShapeStyle(LinearGradient(colors: [FishTheme.accent2, FishTheme.accent],
                                                   startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(LinearGradient(colors: [FishTheme.panelHi, FishTheme.panel],
                                                   startPoint: .top, endPoint: .bottom))
                )

            VStack(spacing: 5) {
                BaitGlyph(name: item.bait)
                    .stroke(hot ? FishTheme.accentInk : FishTheme.inkDim,
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 26, height: 26)
                Text(item.bait)
                    .font(FishTheme.display(13, .bold))
                    .foregroundColor(hot ? FishTheme.accentInk : FishTheme.inkDim)
            }

            // faint amber tag on the currently-committed value (when not hot)
            if isCurrent && !hot {
                Circle()
                    .fill(FishTheme.accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: FishTheme.accentGlow, radius: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
            }
        }
        .frame(width: 92, height: 92)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    hot ? Color.clear
                        : (isCurrent ? Color(hex: 0xC9_86_3A, alpha: 1) : FishTheme.line),
                    lineWidth: 1.5
                )
        )
        .shadow(color: hot ? FishTheme.accentGlow : .black.opacity(0.5),
                radius: hot ? 18 : 11, y: hot ? 8 : 8)
        .overlay(
            Group {
                if hot {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(FishTheme.accent.opacity(0.12), lineWidth: 4)
                }
            }
        )
        .scaleEffect(hot ? 1.12 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: hot)
    }

    // MARK: Layout (map options[] onto cardinal/around-the-circle positions)

    private struct LayoutItem: Equatable {
        let bait: String
        let direction: Direction   // for the 4-cardinal case
        let angle: Angle           // for the >4 case (radial spread)
        let usesCardinal: Bool
    }

    /// For exactly 4 options we honour the mockup's fixed mapping order:
    /// options[0]=left, options[1]=up, options[2]=right, options[3]=down
    /// (so the default ["Crawler","Minnow","Lure","Jig"] → Crawler=left,
    ///  Minnow=up, Lure=right, Jig=down, matching the HTML).
    private var layout: [LayoutItem] {
        if options.count == 4 {
            let dirs: [Direction] = [.left, .up, .right, .down]
            return zip(options, dirs).map {
                LayoutItem(bait: $0.0, direction: $0.1, angle: $0.1.angle, usesCardinal: true)
            }
        } else {
            // lay the options around the circle starting at the top
            let n = max(options.count, 1)
            return options.enumerated().map { idx, bait in
                let a = Angle(degrees: -90 + Double(idx) / Double(n) * 360)
                return LayoutItem(bait: bait, direction: .up, angle: a, usesCardinal: false)
            }
        }
    }

    private let petalRadius: CGFloat = 104
    private let hotRadius: CGFloat = 110

    private func petalPosition(_ item: LayoutItem, hot: Bool) -> CGPoint {
        let c = CGPoint(x: 140, y: 140)
        let r = hot ? hotRadius : petalRadius
        if item.usesCardinal {
            switch item.direction {
            case .up:    return CGPoint(x: c.x, y: c.y - r)
            case .down:  return CGPoint(x: c.x, y: c.y + r)
            case .left:  return CGPoint(x: c.x - r, y: c.y)
            case .right: return CGPoint(x: c.x + r, y: c.y)
            case .angular(let a):
                let rad = CGFloat(a.radians)
                return CGPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r)
            }
        } else {
            let rad = CGFloat(item.angle.radians)
            return CGPoint(x: c.x + cos(rad) * r, y: c.y + sin(rad) * r)
        }
    }

    // Resolve the active direction (for the needle) from the hovered bait.
    private var activeDirection: Direction? {
        guard let h = hovered, let item = layout.first(where: { $0.bait == h }) else { return nil }
        if item.usesCardinal { return item.direction }
        // For the angular case fabricate a Direction-like angle holder via .right rotated.
        return Direction.angular(item.angle)
    }

    // MARK: Gesture

    private var pressDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !pressing {
                    beginPress(at: value.startLocation)
                }
                dragPoint = value.location
                if armed {
                    updateHover(to: value.location)
                }
            }
            .onEnded { _ in
                endPress()
            }
    }

    private func beginPress(at point: CGPoint) {
        pressing = true
        pressPoint = point
        dragPoint = point
        hovered = nil
        impact.prepare()
        selectionHaptic.prepare()

        // animate the fill rising over the hold window
        pressProgress = 0
        withAnimation(.linear(duration: holdSeconds)) {
            pressProgress = 1
        }

        // arm the bloom after the hold window
        let work = DispatchWorkItem { armBloom() }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds, execute: work)
    }

    private func armBloom() {
        guard pressing else { return }
        impact.impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            armed = true
        }
        // evaluate initial hover from where the finger currently is
        updateHover(to: dragPoint)
    }

    private func updateHover(to point: CGPoint) {
        guard armed else { return }
        let dx = point.x - pressPoint.x
        let dy = point.y - pressPoint.y
        let dist = hypot(dx, dy)

        let newHover: String?
        if dist < deadZone {
            newHover = nil   // center == cancel
        } else if options.count == 4 {
            // dominant cardinal axis
            let dir: Direction = abs(dx) > abs(dy)
                ? (dx > 0 ? .right : .left)
                : (dy > 0 ? .down : .up)
            newHover = layout.first(where: { $0.direction == dir })?.bait
        } else {
            // nearest petal by angle
            let ang = atan2(dy, dx)
            newHover = layout.min(by: {
                abs(angleDelta($0.angle.radians, ang)) < abs(angleDelta($1.angle.radians, ang))
            })?.bait
        }

        if newHover != hovered {
            hovered = newHover
            selectionHaptic.selectionChanged()
            selectionHaptic.prepare()
        }
    }

    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    private func endPress() {
        pressing = false
        holdWorkItem?.cancel()
        holdWorkItem = nil

        withAnimation(.easeOut(duration: 0.18)) {
            pressProgress = 0
        }

        if armed {
            let commit = hovered
            withAnimation(.easeOut(duration: 0.16)) {
                armed = false
            }
            if let bait = commit {
                selection = bait
                success.notificationOccurred(.success)
                flashCommit()
            }
            hovered = nil
        }
    }

    private func flashCommit() {
        committedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            committedFlash = false
        }
    }
}

// MARK: - Direction

private enum Direction: Equatable {
    case up, down, left, right
    case angular(Angle)

    /// Angle the needle should point (0° = +x / right, 90° = +y / down).
    var angle: Angle {
        switch self {
        case .right:        return .degrees(0)
        case .down:         return .degrees(90)
        case .left:         return .degrees(180)
        case .up:           return .degrees(-90)
        case .angular(let a): return a
        }
    }

    static func == (lhs: Direction, rhs: Direction) -> Bool {
        switch (lhs, rhs) {
        case (.up, .up), (.down, .down), (.left, .left), (.right, .right):
            return true
        case let (.angular(a), .angular(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Bait glyph (simple line shapes echoing the mockup SVGs)

private struct BaitGlyph: Shape {
    let name: String

    func path(in rect: CGRect) -> Path {
        // normalise to a 24x24 viewBox
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s
        let oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }

        var path = Path()
        switch name.lowercased() {
        case "minnow":
            // fish body + tail
            path.move(to: p(3, 12))
            path.addCurve(to: p(18, 12), control1: p(7, 7), control2: p(14, 7))
            path.addCurve(to: p(3, 12), control1: p(14, 17), control2: p(7, 17))
            path.move(to: p(18, 12)); path.addLine(to: p(21, 10))
            path.addLine(to: p(21, 14)); path.addLine(to: p(18, 12))
        case "lure":
            // spoon ellipse + tail
            path.addEllipse(in: CGRect(x: ox + 4 * s, y: oy + 8 * s, width: 14 * s, height: 8 * s))
            path.move(to: p(18, 12)); path.addLine(to: p(22, 10))
            path.addLine(to: p(22, 14)); path.addLine(to: p(18, 12))
        case "jig":
            // hook
            path.move(to: p(9, 4))
            path.addLine(to: p(9, 13))
            path.addArc(center: p(11, 13), radius: 4 * s,
                        startAngle: .degrees(180), endAngle: .degrees(90), clockwise: false)
            path.addEllipse(in: CGRect(x: ox + 7.6 * s, y: oy + 2.6 * s, width: 2.8 * s, height: 2.8 * s))
        default:
            // crawler — a wavy worm (also the resting default)
            path.move(to: p(4, 12))
            path.addCurve(to: p(12, 12), control1: p(7, 9), control2: p(9, 15))
            path.addCurve(to: p(20, 12), control1: p(15, 9), control2: p(17, 15))
        }
        return path
    }
}

#if DEBUG
private struct RadialBaitPicker_Preview: View {
    @State private var bait = "Crawler"
    var body: some View {
        ZStack {
            FishTheme.bg.ignoresSafeArea()
            VStack {
                Spacer()
                RadialBaitPicker(selection: $bait) { /* add new */ }
                    .padding(.horizontal, 18)
                Text("Selected: \(bait)")
                    .font(FishTheme.mono(11, .regular))
                    .foregroundColor(FishTheme.inkDim)
                    .padding(.top, 24)
                Spacer()
            }
        }
    }
}

#Preview {
    RadialBaitPicker_Preview()
}
#endif
