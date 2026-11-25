//
// LiveActivityKit.swift
// TempoWidget
//
// What the three Live Activities (workout, focus timer, guided run) share in
// the Tide look: one tone per activity, the glass-dark lock-screen field, the
// symbol tile, and the rule for how big a lock screen may get at large text.
// The tokens are the app's own (`Tide`), see TideWidgetKit.swift.
//

import SwiftUI
import WidgetKit

// MARK: - ActivityTone

/// One colour per activity, so two running at once read apart in the island.
enum ActivityTone {
    static let workout = Tide.streak
    static let focus = Tide.fat
    static let run = Tide.success
}

// MARK: - ActivityTile

/// A symbol on a soft tinted tile: the leading mark of a lock-screen row.
struct ActivityTile: View {
    let symbol: String
    let tone: Color
    var size: CGFloat = Tide.s10

    var body: some View {
        Image(systemName: symbol)
            .font(.tideGlyph(size * WidgetMetrics.glyphShare))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tone)
            .frame(width: size, height: size)
            .background(tone.opacity(0.16), in: .rect(cornerRadius: size * WidgetMetrics.tileCorner, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Lock-screen field

extension View {
    /// The lock-screen and banner field: the ink, lit from the corner by the
    /// activity's tone. The tint is kept see-through so the system material
    /// still shows, which keeps the banner readable on any wallpaper.
    func tideActivityField(_ tone: Color) -> some View {
        background {
            RadialGradient(
                colors: [tone.opacity(0.26), .clear],
                center: .topLeading, startRadius: 0, endRadius: WidgetMetrics.bannerGlow
            )
        }
        .activityBackgroundTint(Tide.ink.opacity(0.88))
        .activitySystemActionForegroundColor(tone)
    }
}

// MARK: - ActivityReadout

/// A number or a clock in the app's condensed numerals, right-aligned under a
/// small label: the trailing column of every lock-screen row.
struct ActivityReadout<Value: View>: View {
    let label: String
    var tone: Color = Tide.text2
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .trailing, spacing: Tide.hair) {
            // The tracked capitals run a hair past their measured width: the
            // Dynamic Island's tight trailing column cut the last letter off.
            WidgetLabel(label, color: tone)
                .padding(.trailing, Tide.hair)
            value()
                .font(Tide.numeral(Tide.numeralM))
                .foregroundStyle(Tide.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Clock text

extension Text {
    /// A live countdown to `end`. The range is clamped, so a countdown that
    /// already ended shows 0:00 instead of trapping (see `SafeTimerRange`).
    static func countdown(to end: Date) -> Text {
        Text(timerInterval: SafeTimerRange.countdown(to: end), countsDown: true)
    }
}
