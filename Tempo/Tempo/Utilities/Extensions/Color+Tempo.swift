//
// Color+Tempo.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

extension Color {
    // MARK: - Backgrounds

    static let tempoBgPrimary = Color("tempo-bg-primary")
    static let tempoBgSecondary = Color("tempo-bg-secondary")
    static let tempoBgTertiary = Color("tempo-bg-tertiary")

    // MARK: - Surfaces

    static let tempoSurfaceCard = Color("tempo-surface-card")
    static let tempoSurfaceSheet = Color("tempo-surface-sheet")
    static let tempoSurfaceElevated = Color("tempo-surface-elevated")

    // MARK: - Primary

    static let tempoInk = Color("tempo-ink")
    static let tempoBone = Color("tempo-bone")
    static let tempoSignal = Color("tempo-signal")
    static let tempoSignalPressed = Color("tempo-signal-pressed")

    // MARK: - Secondary

    static let tempoSteel = Color("tempo-steel")
    static let tempoConcrete = Color("tempo-concrete")
    static let tempoAsh = Color("tempo-ash")

    // MARK: - Accent

    static let tempoAmber = Color("tempo-amber")
    static let tempoElectric = Color("tempo-electric")
    static let tempoViolet = Color("tempo-violet")

    /// The user-selected accent color (Appearance settings). Resolves the
    /// `accentColorChoice` UserDefaults key written by the accent picker.
    /// Falls back to Signal Red. NOTE: this is a static read — SwiftUI views
    /// that must re-tint live when the choice changes should observe it via
    /// `@AppStorage("accentColorChoice")` and pass the resolved color into
    /// `.tint(...)`, since a `static let`/computed `Color` won't trigger a
    /// re-render on its own. See `ContentView.accentColor`.
    static var tempoAccent: Color {
        let raw = UserDefaults.standard.string(forKey: "accentColorChoice")
        switch raw {
        case "electric_blue": return .tempoElectric
        case "success_green": return .tempoSuccess
        default: return .tempoSignal
        }
    }

    // MARK: - Semantic

    static let tempoSuccess = Color("tempo-success")
    static let tempoWarning = Color("tempo-warning")
    static let tempoError = Color("tempo-error")
    static let tempoInfo = Color("tempo-info")

    // MARK: - Text

    static let tempoTextPrimary = Color("tempo-text-primary")
    static let tempoTextSecondary = Color("tempo-text-secondary")
    static let tempoTextTertiary = Color("tempo-text-tertiary")
    static let tempoTextDisabled = Color("tempo-text-disabled")
    static let tempoTextInverse = Color("tempo-text-inverse")

    // MARK: - Borders

    static let tempoBorder = Color("tempo-border")
    static let tempoBorderFocused = Color("tempo-border-focused")
    static let tempoBorderError = Color("tempo-border-error")
    static let tempoDivider = Color("tempo-divider")
    static let tempoDividerHeavy = Color("tempo-divider-heavy")

    // MARK: - Recovery Zones

    static let tempoRecoveryGreen = Color("tempo-recovery-green")
    static let tempoRecoveryGreenBg = Color("tempo-recovery-green-bg")
    static let tempoRecoveryYellow = Color("tempo-recovery-yellow")
    static let tempoRecoveryYellowBg = Color("tempo-recovery-yellow-bg")
    static let tempoRecoveryRed = Color("tempo-recovery-red")
    static let tempoRecoveryRedBg = Color("tempo-recovery-red-bg")

    // MARK: - Training

    /// PR Gold — #FFD700
    static let tempoPRGold = Color(red: 1, green: 215 / 255, blue: 0)

    // MARK: - Nutrition Macro Colors

    /// Protein — #5AC8FA
    static let tempoMacroProtein = Color(red: 90 / 255, green: 200 / 255, blue: 250 / 255)
    /// Carbs — #FFD60A
    static let tempoMacroCarbs = Color(red: 255 / 255, green: 214 / 255, blue: 10 / 255)
    /// Fat — #FF9F0A
    static let tempoMacroFat = Color(red: 255 / 255, green: 159 / 255, blue: 10 / 255)

    // MARK: - Sleep Stage Colors

    /// Sleep Awake — #FF6B6B
    static let tempoSleepAwake = Color(red: 1.0, green: 107 / 255, blue: 107 / 255)
    /// Sleep Light — #74B9FF
    static let tempoSleepLight = Color(red: 116 / 255, green: 185 / 255, blue: 1.0)
    /// Sleep Deep — #0652DD
    static let tempoSleepDeep = Color(red: 6 / 255, green: 82 / 255, blue: 221 / 255)
    /// Sleep REM / HRV — #A29BFE
    static let tempoSleepREM = Color(red: 162 / 255, green: 155 / 255, blue: 254 / 255)

    // MARK: - Dark Mode Component Colors

    /// Dark gray fill — #383838 / #38383A
    static let tempoFillTertiary = Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)
    /// Input background dark — #262626
    static let tempoInputBgDark = Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
    /// Input background light — #F3F4F6
    static let tempoInputBgLight = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    /// Signal pressed / highlight — #FF4D5A
    static let tempoSignalHighlight = Color(red: 255 / 255, green: 77 / 255, blue: 90 / 255)
    /// Error light — #F87171
    static let tempoErrorLight = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
    /// Secondary fill dark — #48484A
    static let tempoFillSecondary = Color(red: 72 / 255, green: 72 / 255, blue: 74 / 255)
    /// Tertiary text dark — #52525B
    static let tempoPlaceholder = Color(red: 82 / 255, green: 82 / 255, blue: 91 / 255)
    /// Deep dark surface — #1C1C1E
    static let tempoSurfaceDeep = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
}
