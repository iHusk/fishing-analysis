import SwiftUI
import QuartzCore
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// A momentum drag tape-measure control — the hero input of the catch screen.
///
/// A horizontal tape of ticks scrolls under a fixed center amber indicator
/// (`FishTheme.accent`). A large numeric readout sits above. Drag to scrub;
/// on release the tape glides with inertia and settles on the nearest snapped
/// value. Values snap to `step`, clamp to `range`, and a light selection haptic
/// fires every time the snapped value changes — during the drag AND during the
/// momentum glide as each snap is crossed.
///
/// This is the inertial evolution of `RulerInput` (which is 1:1 with no glide).
/// Tick/snap/haptic math is reused from there; the new behavior is the
/// velocity-driven decelerating settle.
///
/// Used for Length (step 0.25, majorEvery 4) and Depth (step 0.5, majorEvery 2).
struct TapeInput: View {
    @Binding var value: Double

    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    /// Draw an emphasized (taller, labeled) tick every `majorEvery` steps.
    let majorEvery: Int
    /// Number formatting for the readout & major-tick labels (e.g. "%g").
    var format: String = "%g"
    /// Point size of the big numeric readout — Length is the hero, Depth compact.
    var readoutSize: CGFloat = 48
    /// Height of the scrubbable tape band.
    var tapeHeight: CGFloat = 86

    /// Spacing in points between adjacent `step` ticks.
    private let pointsPerStep: CGFloat = 24

    init(value: Binding<Double>,
         range: ClosedRange<Double>,
         step: Double,
         unit: String,
         majorEvery: Int,
         format: String = "%g",
         readoutSize: CGFloat = 48,
         tapeHeight: CGFloat = 86) {
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.majorEvery = majorEvery
        self.format = format
        self.readoutSize = readoutSize
        self.tapeHeight = tapeHeight
    }

    // MARK: - State

    /// Continuous (un-snapped) position in *value units*, drives tick offset.
    /// Kept separate from `value` so the tape can move smoothly between snaps.
    @State private var position: Double = .nan
    /// Value at the moment the active drag began.
    @State private var dragStartPosition: Double = 0
    /// Last snapped value we emitted a haptic tick for.
    @State private var lastTickedValue: Double?
    /// True while a finger is down.
    @State private var isDragging = false

    // Momentum glide bookkeeping (TimelineView-driven decay loop).
    @State private var isGliding = false
    /// Velocity in *value units per second* at the moment of release.
    @State private var glideVelocity: Double = 0
    /// Wall-clock start of the current glide.
    @State private var glideStartDate: Date = .distantPast
    /// Position at the moment the glide began.
    @State private var glideStartPosition: Double = 0
    /// Target snapped value the glide is settling onto.
    @State private var glideTarget: Double = 0
    /// Total glide duration, scaled to release velocity.
    @State private var glideDuration: Double = 0

    /// Recent drag samples (time, translationWidth) for finite-difference velocity.
    @State private var velocitySamples: [(t: TimeInterval, x: CGFloat)] = []

    #if canImport(UIKit) && !os(watchOS)
    private let selectionHaptic = UISelectionFeedbackGenerator()
    #endif

    // MARK: - Derived

    private func clamp(_ v: Double) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }

    private func snap(_ v: Double) -> Double {
        let c = clamp(v)
        let snapped = (c / step).rounded() * step
        return clamp(snapped)
    }

    /// The committed, snapped value shown in the readout / bound out.
    private var displayValue: Double { clamp(value) }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 6) {
            readout
            tapeBand
        }
        .padding(.vertical, 4)
        .onAppear {
            if position.isNaN { position = clamp(value) }
        }
        .onChange(of: value) { _, newValue in
            // External changes (carry-forward, accessibility) re-center the tape
            // when we are not actively scrubbing or gliding.
            if !isDragging && !isGliding {
                position = clamp(newValue)
            }
        }
        // Accessibility: treat the whole control as one adjustable element.
        .accessibilityElement()
        .accessibilityLabel(unit)
        .accessibilityValue(String(format: format, displayValue) + " " + unit)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: step)
            case .decrement: adjust(by: -step)
            @unknown default: break
            }
        }
    }

    // MARK: - Readout

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(String(format: format, displayValue))
                .font(FishTheme.display(readoutSize, .bold))
                .monospacedDigit()
                .foregroundStyle(FishTheme.ink)
                .shadow(color: FishTheme.accentGlow.opacity(0.6), radius: readoutSize * 0.35, y: 2)
            Text(unit)
                .font(FishTheme.display(max(13, readoutSize * 0.36), .semibold))
                .foregroundStyle(FishTheme.inkDim)
                .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tape band

    private var tapeBand: some View {
        GeometryReader { geo in
            ZStack {
                ticks(width: geo.size.width)
                centerIndicator
            }
            .frame(width: geo.size.width, height: tapeHeight)
            // Fade the tape toward the edges so ticks dissolve, not clip hard.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.16),
                        .init(color: .black, location: 0.84),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .contentShape(Rectangle())
            .gesture(drag(width: geo.size.width))
            // Drive the momentum glide off the display refresh clock.
            .background(glideDriver)
        }
        .frame(height: tapeHeight)
    }

    private var centerIndicator: some View {
        ZStack {
            // Soft glow behind the line.
            Rectangle()
                .fill(FishTheme.accentGlow)
                .frame(width: 14)
                .blur(radius: 7)
            // The crisp amber line, fading toward the bottom.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [FishTheme.accent, FishTheme.accent.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .cornerRadius(2)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            // Triangle caps top & bottom, instrument-needle feel.
            Triangle()
                .fill(FishTheme.accent)
                .frame(width: 12, height: 8)
        }
        .overlay(alignment: .bottom) {
            Triangle()
                .fill(FishTheme.accent)
                .frame(width: 12, height: 8)
                .rotationEffect(.degrees(180))
        }
        .allowsHitTesting(false)
    }

    // MARK: - Ticks

    /// Draws the ticks visible across `width`, offset so the current continuous
    /// `position` sits under the center indicator. Only MAJOR ticks are labeled.
    private func ticks(width: CGFloat) -> some View {
        let center = width / 2
        let pos = position.isNaN ? clamp(value) : position
        let posIndex = (pos - range.lowerBound) / step

        let halfSpanSteps = Int(center / pointsPerStep) + 2
        let firstIndex = Int(posIndex.rounded()) - halfSpanSteps
        let lastIndex = Int(posIndex.rounded()) + halfSpanSteps

        let lowIndex = 0
        let highIndex = Int(((range.upperBound) - range.lowerBound) / step)

        let visibleLow = max(firstIndex, lowIndex)
        let visibleHigh = min(lastIndex, highIndex)

        return ZStack(alignment: .topLeading) {
            if visibleLow <= visibleHigh {
                ForEach(visibleLow...visibleHigh, id: \.self) { i in
                    let isMajor = (i % majorEvery == 0)
                    let x = center + (CGFloat(i) - CGFloat(posIndex)) * pointsPerStep
                    tick(index: i, isMajor: isMajor, x: x)
                }
            }
        }
    }

    @ViewBuilder
    private func tick(index i: Int, isMajor: Bool, x: CGFloat) -> some View {
        let tickHeight: CGFloat = isMajor ? 40 : 18
        let tickValue = range.lowerBound + Double(i) * step

        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(isMajor ? FishTheme.ink.opacity(0.85) : FishTheme.line)
                .frame(width: isMajor ? 2 : 1.4, height: tickHeight)
            if isMajor {
                Text(String(format: format, tickValue))
                    .font(FishTheme.mono(11, .regular))
                    .foregroundStyle(FishTheme.inkFaint)
                    .monospacedDigit()
                    .fixedSize()
            } else {
                // Reserve label height so minor & major ticks share a baseline.
                Spacer(minLength: 0).frame(height: 14)
            }
        }
        .frame(width: 1)
        .position(x: x, y: tapeHeight / 2)
    }

    // MARK: - Drag

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !isDragging {
                    beginDrag()
                }
                recordSample(g.translation.width)
                // Drag right -> value increases (pull the tape left under the
                // finger, exposing higher numbers to the right of center). We
                // move the tape so dragging right reveals higher values, which
                // means position increases with translation.width.
                let deltaSteps = Double(g.translation.width / pointsPerStep)
                let newPos = clamp(dragStartPosition + deltaSteps * step)
                position = newPos
                commitIfSnapChanged(newPos)
            }
            .onEnded { g in
                isDragging = false
                let v = releaseVelocity(predicted: g.predictedEndTranslation.width,
                                        last: g.translation.width)
                startGlide(velocityStepsPerSec: v)
            }
    }

    private func beginDrag() {
        isDragging = true
        isGliding = false
        velocitySamples.removeAll(keepingCapacity: true)
        dragStartPosition = position.isNaN ? clamp(value) : position
        #if canImport(UIKit) && !os(watchOS)
        selectionHaptic.prepare()
        #endif
    }

    private func recordSample(_ x: CGFloat) {
        let now = CACurrentMediaTimeOrNow()
        velocitySamples.append((t: now, x: x))
        // Keep only the last ~80ms of samples for a stable finite difference.
        let cutoff = now - 0.08
        velocitySamples.removeAll { $0.t < cutoff }
    }

    /// Returns release velocity in *value units per second*.
    /// Prefers DragGesture's predicted end translation; falls back to a
    /// finite difference of the recent samples if the prediction is degenerate.
    private func releaseVelocity(predicted: CGFloat, last: CGFloat) -> Double {
        // Predicted translation models a ~0.35s fling; convert to points/sec.
        let predictedPointsPerSec = Double(predicted - last) / 0.35

        var pointsPerSec = predictedPointsPerSec
        if abs(pointsPerSec) < 1, let first = velocitySamples.first,
           let lastSample = velocitySamples.last, lastSample.t > first.t {
            let dt = lastSample.t - first.t
            pointsPerSec = Double(lastSample.x - first.x) / dt
        }
        // Convert points/sec -> value-units/sec.
        return (pointsPerSec / Double(pointsPerStep)) * step
    }

    // MARK: - Momentum glide

    /// A zero-size view that runs a TimelineView animation clock while gliding,
    /// advancing `position` along an ease-out decay and snapping at the end.
    @ViewBuilder
    private var glideDriver: some View {
        if isGliding {
            TimelineView(.animation) { timeline in
                Color.clear
                    .onChange(of: timeline.date) { _, date in
                        stepGlide(now: date)
                    }
            }
        } else {
            Color.clear
        }
    }

    private func startGlide(velocityStepsPerSec v: Double) {
        let start = position.isNaN ? clamp(value) : position

        // Below a small threshold there is no meaningful fling: snap directly.
        guard abs(v) > step * 1.5 else {
            settle(to: snap(start))
            return
        }

        // Exponential decay: distance traveled = v / k (k = decay rate /sec).
        let k = 5.0
        let projected = start + v / k
        let target = snap(projected)

        glideStartPosition = start
        glideVelocity = v
        glideTarget = target
        glideStartDate = Date()
        // Duration scales with velocity, capped for responsiveness.
        glideDuration = min(1.1, max(0.18, abs(v) / (step * 28)))
        isGliding = true
    }

    private func stepGlide(now date: Date) {
        guard isGliding else { return }
        let elapsed = date.timeIntervalSince(glideStartDate)
        let p = min(1.0, elapsed / glideDuration)

        // Ease-out cubic: fast then decelerating, lands exactly on target.
        let eased = 1 - pow(1 - p, 3)
        let newPos = clamp(glideStartPosition + (glideTarget - glideStartPosition) * eased)
        position = newPos
        commitIfSnapChanged(newPos)

        if p >= 1.0 {
            isGliding = false
            settle(to: glideTarget)
        }
    }

    /// Final landing: pin continuous position to the snapped value and commit.
    private func settle(to snapped: Double) {
        withAnimation(.easeOut(duration: 0.12)) {
            position = snapped
        }
        commitIfSnapChanged(snapped, force: true)
    }

    // MARK: - Commit + haptics

    /// Snaps `rawPosition`, writes through to `value` if changed, and fires a
    /// selection haptic whenever the *snapped* value crosses to a new tick.
    private func commitIfSnapChanged(_ rawPosition: Double, force: Bool = false) {
        let snapped = snap(rawPosition)
        if snapped != value {
            value = snapped
        }
        if force || lastTickedValue != snapped {
            lastTickedValue = snapped
            #if canImport(UIKit) && !os(watchOS)
            selectionHaptic.selectionChanged()
            selectionHaptic.prepare()
            #endif
        }
    }

    private func adjust(by delta: Double) {
        // Cancel any in-flight motion, then step one snap.
        isGliding = false
        isDragging = false
        let next = snap(clamp(displayValue + delta))
        withAnimation(.easeOut(duration: 0.14)) {
            position = next
        }
        commitIfSnapChanged(next, force: true)
    }

    // MARK: - Time helpers

    /// Monotonic media time in seconds, for drag-sample velocity.
    private func CACurrentMediaTimeOrNow() -> TimeInterval {
        CACurrentMediaTime()
    }
}

/// A simple upward-pointing triangle for the indicator caps.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#if DEBUG
private struct TapeInputPreview: View {
    @State private var length = 18.5
    @State private var depth = 22.0
    var body: some View {
        VStack(spacing: 28) {
            TapeInput(value: $length, range: 0...60, step: 0.25,
                      unit: "in", majorEvery: 4)
            TapeInput(value: $depth, range: 0...300, step: 0.5,
                      unit: "ft", majorEvery: 2)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FishTheme.bg)
    }
}

#Preview {
    TapeInputPreview()
}
#endif
