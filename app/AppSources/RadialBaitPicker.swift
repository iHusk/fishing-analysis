//
//  RadialBaitPicker.swift
//  FishingLogger
//
//  Press-and-hold radial bait selector (ported from wireframes/claude/bait-picker-radial.html).
//
//  Architecture note: the radial bloom must draw over the WHOLE screen, but the
//  resting row is only ~74pt tall. So the row and the full-screen overlay are split:
//    - `RadialBaitPicker`  — the resting row + the press/drag gesture. It writes press
//                            state into a shared `BaitRadialController`.
//    - `BaitRadialOverlay` — a full-screen, non-interactive view that CatchEntryView
//                            places in its root layer; it reads the controller and draws
//                            the scrim + petals + hub at the touch point (global coords).
//
//  Interaction: hold ~0.32s → bloom from the touch point → flick to a cardinal
//  direction (Minnow up / Lure right / Jig down / Crawler left) → release commits;
//  releasing on center cancels. Haptics: light on bloom, selection on hover change,
//  success on commit.
//

import SwiftUI
import UIKit
import Combine

// MARK: - Shared controller (bridges the row gesture → the full-screen overlay)

@MainActor
final class BaitRadialController: ObservableObject {
    @Published var armed = false
    @Published var pressPoint: CGPoint = .zero
    @Published var hovered: String? = nil
    @Published var options: [String] = ["Crawler", "Minnow", "Lure", "Jig"]
    @Published var current: String = ""
}

// MARK: - Resting row + gesture

struct RadialBaitPicker: View {

    @Binding private var selection: String
    private let options: [String]
    private let onAddNew: (() -> Void)?
    @ObservedObject private var controller: BaitRadialController

    init(selection: Binding<String>,
         controller: BaitRadialController,
         options: [String] = ["Crawler", "Minnow", "Lure", "Jig"],
         onAddNew: (() -> Void)? = nil) {
        self._selection = selection
        self.controller = controller
        self.options = options
        self.onAddNew = onAddNew
    }

    // press / arm state (local to the row)
    @State private var pressing = false
    @State private var pressProgress: CGFloat = 0
    @State private var holdWorkItem: DispatchWorkItem?
    @State private var breathe = false
    @State private var committedFlash = false

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let success = UINotificationFeedbackGenerator()

    private let holdSeconds: Double = 0.32
    private let deadZone: CGFloat = 34

    var body: some View {
        restingContent
            .gesture(pressDragGesture)
            .onAppear {
                impact.prepare(); selectionHaptic.prepare(); success.prepare()
                breathe = true
                controller.options = options
                controller.current = selection
            }
            .onChange(of: selection) { _, new in controller.current = new }
    }

    private var restingContent: some View {
        ZStack {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [FishTheme.panelHi, FishTheme.panel],
                                             startPoint: .top, endPoint: .bottom))
                    LinearGradient(colors: [.clear, FishTheme.accent.opacity(0.16)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: geo.size.height * pressProgress)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(FishTheme.accent.opacity(0.12))
                    BaitGlyph(name: selection)
                        .stroke(FishTheme.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .padding(9)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text("BAIT").fishEyebrow()
                    Text(selection)
                        .font(FishTheme.display(24, .bold))
                        .foregroundColor(FishTheme.ink)
                }

                Spacer(minLength: 8)

                HStack(spacing: 7) {
                    Circle().fill(FishTheme.accent).frame(width: 9, height: 9)
                        .shadow(color: FishTheme.accentGlow, radius: 5)
                        .scaleEffect(breathe ? 1.0 : 0.85)
                        .opacity(breathe ? 1.0 : 0.35)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
                    Text("HOLD").font(FishTheme.mono(9, .medium)).tracking(0.8)
                        .foregroundColor(FishTheme.inkFaint)
                }
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 74)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(committedFlash ? FishTheme.accent : (controller.armed ? FishTheme.accent.opacity(0.7) : FishTheme.line),
                              lineWidth: committedFlash ? 1.6 : 1)
                .shadow(color: committedFlash ? FishTheme.accentGlow : .clear, radius: committedFlash ? 10 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: committedFlash)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Gesture

    private var pressDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if !pressing { beginPress(at: value.startLocation) }
                if controller.armed { updateHover(to: value.location) }
            }
            .onEnded { _ in endPress() }
    }

    private func beginPress(at point: CGPoint) {
        pressing = true
        controller.pressPoint = point
        controller.hovered = nil
        impact.prepare(); selectionHaptic.prepare()
        pressProgress = 0
        withAnimation(.linear(duration: holdSeconds)) { pressProgress = 1 }
        let work = DispatchWorkItem { armBloom() }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds, execute: work)
    }

    private func armBloom() {
        guard pressing else { return }
        impact.impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { controller.armed = true }
    }

    private func updateHover(to point: CGPoint) {
        let dx = point.x - controller.pressPoint.x
        let dy = point.y - controller.pressPoint.y
        let dist = hypot(dx, dy)
        let newHover: String?
        if dist < deadZone {
            newHover = nil
        } else if options.count == 4 {
            // cardinal: [0]=left, [1]=up, [2]=right, [3]=down
            if abs(dx) > abs(dy) { newHover = dx > 0 ? options[2] : options[0] }
            else { newHover = dy > 0 ? options[3] : options[1] }
        } else {
            let ang = atan2(dy, dx)
            newHover = options.enumerated().min(by: { a, b in
                abs(angleDelta(angleFor(a.offset), ang)) < abs(angleDelta(angleFor(b.offset), ang))
            }).map { $0.element }
        }
        if newHover != controller.hovered {
            controller.hovered = newHover
            selectionHaptic.selectionChanged(); selectionHaptic.prepare()
        }
    }

    private func angleFor(_ idx: Int) -> Double {
        let n = max(options.count, 1)
        return -.pi / 2 + Double(idx) / Double(n) * 2 * .pi
    }
    private func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    private func endPress() {
        pressing = false
        holdWorkItem?.cancel(); holdWorkItem = nil
        withAnimation(.easeOut(duration: 0.18)) { pressProgress = 0 }
        if controller.armed {
            let commit = controller.hovered
            withAnimation(.easeOut(duration: 0.16)) { controller.armed = false }
            if let bait = commit {
                selection = bait
                success.notificationOccurred(.success)
                committedFlash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { committedFlash = false }
            }
            controller.hovered = nil
        }
    }
}

// MARK: - Full-screen overlay (drawn by CatchEntryView's root layer)

struct BaitRadialOverlay: View {
    @ObservedObject var controller: BaitRadialController

    private let petalRadius: CGFloat = 104
    private let hotRadius: CGFloat = 110
    private let edgePad: CGFloat = 78   // keep petals on-screen near edges

    var body: some View {
        GeometryReader { geo in
            if controller.armed {
                ZStack {
                    // Dimming spotlight scrim, brighter at the touch point.
                    RadialGradient(
                        colors: [Color(hex: 0x08090D, alpha: 0.34), Color(hex: 0x08090D, alpha: 0.86)],
                        center: UnitPoint(x: controller.pressPoint.x / max(geo.size.width, 1),
                                          y: controller.pressPoint.y / max(geo.size.height, 1)),
                        startRadius: 0, endRadius: 460)
                    .ignoresSafeArea()

                    bloom(center: clampedCenter(in: geo.size))
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)   // the gesture lives on the row; overlay is visual only
    }

    /// Keep the bloom fully visible even when the touch is near a screen edge.
    private func clampedCenter(in size: CGSize) -> CGPoint {
        let m = hotRadius + edgePad
        return CGPoint(x: min(max(controller.pressPoint.x, m), size.width - m),
                       y: min(max(controller.pressPoint.y, m), size.height - m))
    }

    private func bloom(center: CGPoint) -> some View {
        ZStack {
            ForEach(Array(controller.options.enumerated()), id: \.element) { idx, bait in
                let hot = controller.hovered == bait
                petal(bait, hot: hot, current: bait == controller.current)
                    .position(petalPosition(idx, center: center, hot: hot))
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hot)
            }
            hub.position(center)
        }
    }

    private var hub: some View {
        let cancel = controller.hovered == nil
        return VStack(spacing: 2) {
            Text("RELEASE TO\nCANCEL")
                .font(FishTheme.mono(8, .regular)).tracking(0.9)
                .multilineTextAlignment(.center).foregroundColor(FishTheme.inkFaint)
            Text(controller.current).font(FishTheme.display(13, .bold)).foregroundColor(FishTheme.ink)
        }
        .frame(width: 74, height: 74)
        .background(Circle().fill(RadialGradient(
            colors: [FishTheme.panelHi, Color(hex: 0x0C0F13)],
            center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 40)))
        .overlay(Circle().strokeBorder(cancel ? FishTheme.inkDim : FishTheme.line, lineWidth: 1.5))
        .scaleEffect(cancel ? 1.04 : 1.0)
        .shadow(color: .black.opacity(0.6), radius: 14, y: 10)
        .animation(.easeOut(duration: 0.1), value: cancel)
    }

    private func petal(_ bait: String, hot: Bool, current: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(hot
                      ? AnyShapeStyle(LinearGradient(colors: [FishTheme.accent2, FishTheme.accent], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(LinearGradient(colors: [FishTheme.panelHi, FishTheme.panel], startPoint: .top, endPoint: .bottom)))
            VStack(spacing: 5) {
                BaitGlyph(name: bait)
                    .stroke(hot ? FishTheme.accentInk : FishTheme.inkDim, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 26, height: 26)
                Text(bait).font(FishTheme.display(13, .bold)).foregroundColor(hot ? FishTheme.accentInk : FishTheme.inkDim)
            }
        }
        .frame(width: 92, height: 92)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .strokeBorder(hot ? Color.clear : (current ? FishTheme.accent.opacity(0.6) : FishTheme.line), lineWidth: 1.5))
        .shadow(color: hot ? FishTheme.accentGlow : .black.opacity(0.5), radius: hot ? 18 : 11, y: 8)
        .scaleEffect(hot ? 1.12 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: hot)
    }

    private func petalPosition(_ idx: Int, center: CGPoint, hot: Bool) -> CGPoint {
        let r = hot ? hotRadius : petalRadius
        let n = max(controller.options.count, 1)
        if n == 4 {
            switch idx {
            case 0: return CGPoint(x: center.x - r, y: center.y)  // left
            case 1: return CGPoint(x: center.x, y: center.y - r)  // up
            case 2: return CGPoint(x: center.x + r, y: center.y)  // right
            default: return CGPoint(x: center.x, y: center.y + r) // down
            }
        }
        let a = -.pi / 2 + Double(idx) / Double(n) * 2 * .pi
        return CGPoint(x: center.x + CGFloat(cos(a)) * r, y: center.y + CGFloat(sin(a)) * r)
    }
}

#if DEBUG
#Preview("Radial overlay (armed)") {
    let c = BaitRadialController()
    c.armed = true
    c.pressPoint = CGPoint(x: 195, y: 430)
    c.current = "Crawler"
    c.hovered = "Minnow"
    return ZStack {
        FishTheme.bg.ignoresSafeArea()
        Text("(press-hold target)").font(FishTheme.mono(11, .regular))
            .foregroundColor(FishTheme.inkFaint).position(x: 195, y: 430)
        BaitRadialOverlay(controller: c).ignoresSafeArea()
    }
}
#endif

// MARK: - Bait glyph (simple line shapes echoing the mockup SVGs)

private struct BaitGlyph: Shape {
    let name: String
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let ox = rect.midX - 12 * s, oy = rect.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        switch name.lowercased() {
        case "minnow":
            path.move(to: p(3, 12))
            path.addCurve(to: p(18, 12), control1: p(7, 7), control2: p(14, 7))
            path.addCurve(to: p(3, 12), control1: p(14, 17), control2: p(7, 17))
            path.move(to: p(18, 12)); path.addLine(to: p(21, 10)); path.addLine(to: p(21, 14)); path.addLine(to: p(18, 12))
        case "lure":
            path.addEllipse(in: CGRect(x: ox + 4 * s, y: oy + 8 * s, width: 14 * s, height: 8 * s))
            path.move(to: p(18, 12)); path.addLine(to: p(22, 10)); path.addLine(to: p(22, 14)); path.addLine(to: p(18, 12))
        case "jig":
            path.move(to: p(9, 4)); path.addLine(to: p(9, 13))
            path.addArc(center: p(11, 13), radius: 4 * s, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: false)
            path.addEllipse(in: CGRect(x: ox + 7.6 * s, y: oy + 2.6 * s, width: 2.8 * s, height: 2.8 * s))
        default:
            path.move(to: p(4, 12))
            path.addCurve(to: p(12, 12), control1: p(7, 9), control2: p(9, 15))
            path.addCurve(to: p(20, 12), control1: p(15, 9), control2: p(17, 15))
        }
        return path
    }
}
