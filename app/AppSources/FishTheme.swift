//
//  FishTheme.swift
//  FishingLogger
//
//  Shared design system: color tokens, typography helpers, and a couple of
//  small reusable view helpers used across the catch-entry UI.
//
//  Visual target: dark "instrument" aesthetic — near-black background, a single
//  warm amber accent, Sora for display type, DM Mono for labels. See the
//  wireframes (tape-wheel.html / bait-picker-radial.html) for the look.
//
//  Self-contained: no external dependencies. If the Sora / DM Mono custom fonts
//  are not registered in the app bundle, iOS silently falls back to the system
//  font, which is an acceptable graceful degradation.
//

import SwiftUI

// MARK: - Color hex initializer

extension Color {
    /// Create a Color from an 0xRRGGBB hex literal, e.g. `Color(hex: 0xffb547)`.
    /// - Parameters:
    ///   - hex: 24-bit RGB value (red in the high byte).
    ///   - alpha: opacity, 0...1. Defaults to fully opaque.
    init(hex: UInt, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - FishTheme

/// The shared design system for FishingLogger.
///
/// All colors are referenced through these tokens so the whole app can be
/// retuned from one place. Two typography helpers — `display` (Sora) and
/// `mono` (DM Mono) — produce the two font families used throughout.
enum FishTheme {

    // MARK: Surfaces

    /// App background — near-black.
    static let bg = Color(hex: 0x0d0f12)
    /// Elevated surface (cards, rows).
    static let panel = Color(hex: 0x15181e)
    /// Brighter elevated surface (popovers, gradient tops).
    static let panelHi = Color(hex: 0x1c2027)
    /// Hairline border — white at ~8% alpha.
    static let line = Color(hex: 0xffffff, alpha: 0.08)

    // MARK: Ink (text)

    /// Primary text — white at ~92%.
    static let ink = Color(hex: 0xffffff, alpha: 0.92)
    /// Secondary text — white at ~55%.
    static let inkDim = Color(hex: 0xffffff, alpha: 0.55)
    /// Tertiary text / eyebrow labels — white at ~30%.
    static let inkFaint = Color(hex: 0xffffff, alpha: 0.30)

    // MARK: Accent

    /// Primary accent — warm amber.
    static let accent = Color(hex: 0xffb547)
    /// Lighter amber, used as the top of accent gradients.
    static let accent2 = Color(hex: 0xffc96b)
    /// Text drawn on top of the amber accent — very dark brown.
    static let accentInk = Color(hex: 0x1a1206)
    /// Amber glow, low alpha — for shadows / halos around accented elements.
    static let accentGlow = Color(hex: 0xffb547, alpha: 0.50)

    // MARK: Secondary hue

    /// Cyan — used for the GPS pill / location chips.
    static let cyan = Color(hex: 0x5fd0e0)

    // MARK: - Typography

    /// Sora display font. Falls back to the system rounded design if Sora is
    /// not registered in the bundle.
    /// - Parameters:
    ///   - size: point size.
    ///   - weight: desired weight (mapped onto the registered Sora face).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        // `Font.custom(_:size:)` returns the system font when the family is not
        // present, so applying `.weight(_:)` keeps a sensible result either way.
        Font.custom("Sora", size: size).weight(weight)
    }

    /// DM Mono label font. Falls back to the system monospaced font if DM Mono
    /// is not registered in the bundle.
    /// - Parameters:
    ///   - size: point size.
    ///   - weight: desired weight. DM Mono ships Regular and Medium faces;
    ///     `.medium` (or heavier) maps to "DMMono-Medium", everything else to
    ///     "DMMono-Regular".
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face: String = (weight >= .medium) ? "DMMono-Medium" : "DMMono-Regular"
        // If the PostScript face name isn't found, iOS falls back to system;
        // we still pass the weight through so the fallback is reasonable.
        return Font.custom(face, size: size).weight(weight)
    }
}

// MARK: - Font.Weight ordering

private extension Font.Weight {
    /// Rough numeric ordering so we can compare weights (no Comparable conformance
    /// exists on `Font.Weight`).
    var sortRank: Int {
        switch self {
        case .ultraLight: return 100
        case .thin:       return 200
        case .light:      return 300
        case .regular:    return 400
        case .medium:     return 500
        case .semibold:   return 600
        case .bold:       return 700
        case .heavy:      return 800
        case .black:      return 900
        default:          return 400
        }
    }

    static func >= (lhs: Font.Weight, rhs: Font.Weight) -> Bool {
        lhs.sortRank >= rhs.sortRank
    }
}

// MARK: - Reusable view helpers

/// A rounded panel surface: `FishTheme.panel` fill with a hairline
/// `FishTheme.line` border. Corner radius defaults to 16 to match the
/// wireframe rows / cards.
struct FishPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FishTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(FishTheme.line, lineWidth: 1)
            )
    }
}

extension View {
    /// Wrap the view in a standard FishTheme panel surface (rounded fill +
    /// hairline border). Pass a custom `cornerRadius` if needed.
    func fishPanel(cornerRadius: CGFloat = 16) -> some View {
        modifier(FishPanelModifier(cornerRadius: cornerRadius))
    }

    /// Style a `Text` (or any view) as an uppercase mono eyebrow label:
    /// DM Mono 11 / medium, wide tracking, faint ink.
    func fishEyebrow() -> some View {
        self
            .font(FishTheme.mono(11, .medium))
            .tracking(2.0)
            .textCase(.uppercase)
            .foregroundStyle(FishTheme.inkFaint)
    }
}
