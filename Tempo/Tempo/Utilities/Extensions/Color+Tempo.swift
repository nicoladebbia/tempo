//
// Color+Tempo.swift
// Tempo
//
// The older Tempo* colour names, now answered by the Tide design system
// (docs/UI_REWORK_PLAN.md). Every screen that still uses these names gets
// the Tide look. The app is dark only. New code uses `Tide.*` directly.
//

import SwiftUI

extension Color {
    // MARK: - Backgrounds

    /// The page colour. Whole pages use `.tidePage()` instead, which puts the
    /// living field behind them; this stays for scrims and cut-outs.
    static let tempoBgPrimary = Tide.ink
    static let tempoBgSecondary = Color.white.opacity(0.06)
    static let tempoBgTertiary = Color.white.opacity(0.10)

    // MARK: - Surfaces

    static let tempoSurfaceCard = Tide.fill
    static let tempoSurfaceSheet = Color(red: 0.06, green: 0.08, blue: 0.13)
    static let tempoSurfaceElevated = Color.white.opacity(0.13)

    // MARK: - Primary

    static let tempoInk = Tide.ink
    /// Light foreground (old "bone white").
    static let tempoBone = Tide.text
    /// The accent follows the day's mood: it is the tint the shell sets.
    static var tempoSignal: Color { .accentColor }
    static var tempoSignalPressed: Color { .accentColor.opacity(0.85) }

    // MARK: - Secondary

    static let tempoSteel = Tide.text2
    static let tempoConcrete = Tide.text3
    static let tempoAsh = Color.white.opacity(0.32)

    // MARK: - Accent

    static let tempoAmber = Color(red: 1.00, green: 0.80, blue: 0.40)
    static let tempoElectric = Tide.water
    static let tempoViolet = Color(red: 0.72, green: 0.62, blue: 1.00)

    static var tempoAccent: Color { .accentColor }

    // MARK: - Semantic

    static let tempoSuccess = Color(red: 0.42, green: 0.94, blue: 0.66)
    static let tempoWarning = Color(red: 1.00, green: 0.80, blue: 0.40)
    static let tempoError = Tide.danger
    static let tempoInfo = Color(red: 0.62, green: 0.74, blue: 1.00)

    // MARK: - Text

    static let tempoTextPrimary = Tide.text
    static let tempoTextSecondary = Tide.text2
    static let tempoTextTertiary = Tide.text3
    static let tempoTextDisabled = Color.white.opacity(0.38)
    /// Text on the accent or on any bright fill.
    static let tempoTextInverse = Tide.ink

    // MARK: - Borders

    static let tempoBorder = Tide.hairline
    static var tempoBorderFocused: Color { .accentColor }
    static let tempoBorderError = Tide.danger
    static let tempoDivider = Color.white.opacity(0.10)
    static let tempoDividerHeavy = Color.white.opacity(0.20)

    // MARK: - Recovery Zones

    static let tempoRecoveryGreen = Color(red: 0.42, green: 0.94, blue: 0.66)
    static let tempoRecoveryGreenBg = Color(red: 0.42, green: 0.94, blue: 0.66).opacity(0.16)
    static let tempoRecoveryYellow = Color(red: 1.00, green: 0.80, blue: 0.40)
    static let tempoRecoveryYellowBg = Color(red: 1.00, green: 0.80, blue: 0.40).opacity(0.16)
    static let tempoRecoveryRed = Tide.danger
    static let tempoRecoveryRedBg = Tide.danger.opacity(0.16)

    // MARK: - Training

    static let tempoPRGold = Color(red: 1.00, green: 0.84, blue: 0.30)

    // MARK: - Nutrition Macro Colors (the same on every screen)

    static let tempoMacroProtein = Tide.protein
    static let tempoMacroCarbs = Tide.carbs
    static let tempoMacroFat = Tide.fat

    // MARK: - Sleep Stage Colors

    static let tempoSleepAwake = Tide.danger
    static let tempoSleepLight = Color(red: 0.55, green: 0.76, blue: 1.00)
    static let tempoSleepDeep = Color(red: 0.32, green: 0.44, blue: 1.00)
    static let tempoSleepREM = Color(red: 0.72, green: 0.62, blue: 1.00)

    // MARK: - Fills

    static let tempoFillTertiary = Color.white.opacity(0.12)
    static let tempoInputBgDark = Color.white.opacity(0.08)
    static let tempoInputBgLight = Color.white.opacity(0.08)
    static var tempoSignalHighlight: Color { .accentColor }
    static let tempoErrorLight = Tide.danger
    static let tempoFillSecondary = Color.white.opacity(0.18)
    static let tempoPlaceholder = Color.white.opacity(0.45)
    static let tempoSurfaceDeep = Color.white.opacity(0.06)
}
