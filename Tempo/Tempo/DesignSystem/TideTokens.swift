//
// TideTokens.swift
// Tempo
//
// "Tide": the design system for the UI rework (docs/UI_REWORK_PLAN.md).
// New screens use only these tokens. The older Tempo* tokens stay for the
// screens that have not been rebuilt yet.
//

import SwiftUI

enum Tide {
    // MARK: Colour

    /// RGB components of the base ink, kept as numbers so contrast can be tested.
    static let inkRGB: (r: Double, g: Double, b: Double) = (0.027, 0.043, 0.075)
    static let ink = Color(red: inkRGB.r, green: inkRGB.g, blue: inkRGB.b)

    /// Opacities of white text over ink. `tertiary` still clears 4.5:1 (TideTokenTests).
    static let secondaryOpacity = 0.76
    static let tertiaryOpacity = 0.62

    static let text = Color.white
    static let text2 = Color.white.opacity(secondaryOpacity)
    static let text3 = Color.white.opacity(tertiaryOpacity)
    static let hairline = Color.white.opacity(0.14)
    static let fill = Color.white.opacity(0.09)

    // Data colours that keep their meaning whatever the mood is.
    static let protein = Color(red: 1.00, green: 0.58, blue: 0.50)
    static let carbs = Color(red: 1.00, green: 0.83, blue: 0.42)
    static let fat = Color(red: 0.62, green: 0.74, blue: 1.00)
    static let water = Color(red: 0.36, green: 0.78, blue: 1.00)
    static let streak = Color(red: 1.00, green: 0.66, blue: 0.36)
    static let danger = Color(red: 1.00, green: 0.45, blue: 0.47)

    // MARK: Layout (4 pt grid)

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let edge: CGFloat = 20
    /// Smallest tap target.
    static let hit: CGFloat = 44

    static let cardRadius: CGFloat = 28
    static let tileRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14

    // MARK: Sizes

    /// The hero dial on Today.
    static let dialHero: CGFloat = 164
    /// Numeral sizes at the default text size: hero figure, tile figure, inline figure.
    static let numeralL: CGFloat = 44
    static let numeralM: CGFloat = 34
    static let numeralS: CGFloat = 20
    /// Leading symbol in a card or row.
    static let icon: CGFloat = 28
    /// Level bars: standard and slim.
    static let bar: CGFloat = 6
    static let barSlim: CGFloat = 4

    // MARK: Type (all scale with Dynamic Type)

    static let largeTitle = Font.system(.largeTitle, weight: .bold)
    static let title = Font.system(.title, weight: .bold)
    static let title2 = Font.system(.title2, weight: .bold)
    static let headline = Font.system(.headline, weight: .semibold)
    static let body = Font.system(.subheadline)
    static let bodyStrong = Font.system(.subheadline, weight: .semibold)
    static let caption = Font.system(.footnote, weight: .medium)
    static let label = Font.system(.caption2, weight: .semibold)

    /// Condensed tabular figures: the look of every number in the app.
    /// `size` is the size at the default text size; pass an already scaled value
    /// (`@ScaledMetric`) or use `TideNumber`, which scales for you.
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }

    // MARK: Motion

    /// Taps and state changes: quick, no bounce, interruptible.
    static let snap = Animation.spring(duration: 0.28, bounce: 0.0)
    /// Things that arrive or celebrate.
    static let lively = Animation.spring(duration: 0.38, bounce: 0.22)
    /// Values settling (dial sweep, bars).
    static let settle = Animation.spring(duration: 0.9, bounce: 0.0)
}

// MARK: - Contrast maths (used by tests)

enum TideContrast {
    /// WCAG relative luminance of an sRGB colour.
    static func luminance(r: Double, g: Double, b: Double) -> Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Contrast ratio of white at `opacity` composited over `background`, against that background.
    static func whiteText(opacity: Double, over background: (r: Double, g: Double, b: Double)) -> Double {
        let r = opacity + (1 - opacity) * background.r
        let g = opacity + (1 - opacity) * background.g
        let b = opacity + (1 - opacity) * background.b
        let fg = luminance(r: r, g: g, b: b)
        let bg = luminance(r: background.r, g: background.g, b: background.b)
        return (fg + 0.05) / (bg + 0.05)
    }
}
