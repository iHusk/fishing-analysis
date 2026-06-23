import SwiftUI

/// A horizontal drag-a-ruler (tape-measure) control.
///
/// Drag left/right to scrub the value. The ruler scrolls under a fixed
/// center indicator; a large numeric readout shows the current value.
/// Values snap to `step`, are clamped to `range`, and a light haptic tick
/// fires as you cross each snapped value.
///
/// Used in `CatchEntryView` for Length (0…60 in, 0.25 step) and
/// Depth (0…300 ft, 1 step) in place of the old `Stepper`s.
struct RulerInput: View {
    @Binding var value: Double

    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    /// Spacing in points between adjacent `step` ticks.
    var pointsPerStep: CGFloat = 12
    /// Draw an emphasized (taller, labeled) tick every `majorEvery` steps.
    var majorEvery: Int = 4
    /// Number formatting for the readout (e.g. "%g").
    var format: String = "%g"

    // Drag state: the value at the moment the drag began.
    @State private var dragStartValue: Double?
    // Last snapped value we emitted a haptic tick for.
    @State private var lastTickedValue: Double?

    private var clampedValue: Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: format, clampedValue))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geo in
                ZStack {
                    rulerTicks(width: geo.size.width)

                    // Fixed center indicator.
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(width: geo.size.width))
            }
            .frame(height: 56)
            .clipped()
        }
        .padding(.vertical, 4)
        .accessibilityElement()
        .accessibilityLabel(unit)
        .accessibilityValue(String(format: format, clampedValue) + " " + unit)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(clampedValue + step)
            case .decrement: setValue(clampedValue - step)
            @unknown default: break
            }
        }
    }

    // MARK: - Ticks

    /// Draws ticks across the visible width, offset so that `clampedValue`
    /// sits under the center indicator.
    private func rulerTicks(width: CGFloat) -> some View {
        let center = width / 2
        // Range of step-indices visible given the current value & width.
        let valueIndex = (clampedValue - range.lowerBound) / step
        let halfSpanSteps = Int(center / pointsPerStep) + 2
        let firstIndex = Int(valueIndex.rounded()) - halfSpanSteps
        let lastIndex = Int(valueIndex.rounded()) + halfSpanSteps

        let lowIndex = Int(((range.lowerBound) - range.lowerBound) / step) // 0
        let highIndex = Int(((range.upperBound) - range.lowerBound) / step)

        return ZStack(alignment: .topLeading) {
            ForEach(max(firstIndex, lowIndex)...min(lastIndex, highIndex), id: \.self) { i in
                let isMajor = (i % majorEvery == 0)
                let x = center + (CGFloat(i) - CGFloat(valueIndex)) * pointsPerStep
                tick(index: i, isMajor: isMajor, x: x)
            }
        }
    }

    @ViewBuilder
    private func tick(index i: Int, isMajor: Bool, x: CGFloat) -> some View {
        let tickHeight: CGFloat = isMajor ? 28 : 14
        let tickValue = range.lowerBound + Double(i) * step

        VStack(spacing: 2) {
            Rectangle()
                .fill(isMajor ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.5))
                .frame(width: isMajor ? 2 : 1, height: tickHeight)
            if isMajor {
                Text(String(format: format, tickValue))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .frame(width: 1)
        .position(x: x, y: 16)
    }

    // MARK: - Drag

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let start = dragStartValue ?? clampedValue
                if dragStartValue == nil { dragStartValue = clampedValue }
                // Drag right → value decreases (ruler moves left under finger),
                // matching a physical tape pulled to the right. Invert for the
                // natural "scrub the ruler" feel: drag left increases.
                let deltaSteps = Double(-g.translation.width / pointsPerStep)
                setValue(start + deltaSteps * step)
            }
            .onEnded { _ in
                dragStartValue = nil
            }
    }

    private func setValue(_ raw: Double) {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        let snapped = (clamped / step).rounded() * step
        let bounded = min(max(snapped, range.lowerBound), range.upperBound)
        if bounded != value {
            value = bounded
        }
        if lastTickedValue != bounded {
            lastTickedValue = bounded
            #if canImport(UIKit) && !os(watchOS)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }
}

/// A labeled row that pairs a title with a `RulerInput`.
struct RulerRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var format: String = "%g"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            RulerInput(value: $value,
                       range: range,
                       step: step,
                       unit: unit,
                       format: format)
        }
        .padding(.vertical, 4)
    }
}
