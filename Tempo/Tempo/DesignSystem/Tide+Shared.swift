//
// Tide+Shared.swift
// Tempo
//
// Small pieces the shared components (Views/Shared) are drawn with: a track
// colour, the field surface, a symbol tile and the circular ring. Other
// areas get the same look by using the shared components, not these directly.
//

import SwiftUI

extension Tide {
    /// The unlit part of a ring, dot or bar.
    static let track = Color.white.opacity(0.16)
    /// A fill one step brighter than `fill`: a focused field, a skeleton.
    static let fillStrong = Color.white.opacity(0.15)
    /// A stronger hairline for a focused control.
    static let focusLine: CGFloat = 1.5
    /// Height of a text field row.
    static let fieldHeight: CGFloat = 52
    /// The symbol tile in an empty state.
    static let tileLarge: CGFloat = 64
    /// The symbol tile in a row.
    static let tile: CGFloat = 36
    /// Widest an empty or error state grows on a big screen.
    static let stateWidth: CGFloat = 420
    /// How far the halo reaches past the symbol tile of an empty or error state.
    static let stateHalo: CGFloat = 72
    /// The number being typed in the entry sheet, at the default text size.
    static let numeralReadout: CGFloat = 72
    /// A digit on the entry keypad, and how tall a key is.
    static let numeralKey: CGFloat = 30
    /// The largest a wheel row's digits grow: the row's height is fixed.
    static let numeralWheelMax: CGFloat = 39
    static let keyHeight: CGFloat = 60
    /// The entry sheet at rest, tall enough for the readout, the keys and the Set button.
    static let keypadSheetHeight: CGFloat = 660
    /// The wheel alternative in the entry sheet.
    static let wheelHeight: CGFloat = 320
}

// MARK: - TideFieldSurface

private struct TideFieldSurface: ViewModifier {
    let focused: Bool
    let invalid: Bool
    @Environment(\.tideMood)
    private var mood

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
        content
            .padding(.horizontal, Tide.s4)
            .frame(minHeight: Tide.fieldHeight)
            .background(focused ? Tide.fillStrong : Tide.fill, in: shape)
            .overlay {
                shape.strokeBorder(stroke, lineWidth: focused || invalid ? Tide.focusLine : 1)
            }
            .animation(Tide.snap, value: focused)
            .animation(Tide.snap, value: invalid)
    }

    private var stroke: Color {
        if invalid {
            return Tide.danger
        }
        return focused ? mood.accent : Tide.hairline
    }
}

extension View {
    /// The Tide text field: soft fill, hairline, accent ring while focused,
    /// danger ring when the value is not valid. At least 52 pt tall.
    func tideFieldSurface(focused: Bool = false, invalid: Bool = false) -> some View {
        modifier(TideFieldSurface(focused: focused, invalid: invalid))
    }
}

// MARK: - TideKeyStyle

/// A key on a number pad: a soft tile that lights the instant it is touched,
/// with no easing, so fast typing never waits on an animation.
struct TideKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
        configuration.label
            .foregroundStyle(Tide.text)
            .background(configuration.isPressed ? Tide.fillStrong : Tide.fill, in: shape)
            .contentShape(shape)
            .transaction { $0.animation = nil }
    }
}

// MARK: - TideCardPressStyle

/// A tappable card that dips slightly while pressed.
struct TideCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tide.pressCard : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

// MARK: - TideIconTile

/// A symbol on a soft tinted tile: the leading mark of an empty state or row.
struct TideIconTile: View {
    let systemName: String
    var tint: Color?
    var size: CGFloat = Tide.tile

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric
    private var scale: CGFloat = 1

    var body: some View {
        let color = tint ?? mood.accent
        Image(systemName: systemName)
            // The tile keeps its size, so the symbol stops growing before it
            // can spill out of it (a wide glyph like the dumbbell at AX sizes).
            .font(.system(size: size * 0.44 * min(scale, 1.35), weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: .rect(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - TideRing

/// The circular progress ring: a dim track, a lit arc with a soft glow and a
/// bright head. Smaller sibling of `TideDial`, for rings that carry their own
/// colour (a macro, a goal). The caller puts any text in the middle.
struct TideRing: View {
    /// 0...1.
    let progress: Double
    var color: Color
    var lineWidth: CGFloat = 6
    var glow = true

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var shown: Double = 0

    private var target: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radius = (diameter - lineWidth) / 2
            ZStack {
                Circle()
                    .stroke(Tide.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: glow ? color.opacity(0.5) : .clear, radius: lineWidth * 0.9)
                if shown > 0.02, shown < 0.995 {
                    Circle()
                        .fill(Tide.text.opacity(0.9))
                        .frame(width: lineWidth * 0.42, height: lineWidth * 0.42)
                        .offset(y: -radius)
                        .frame(width: diameter, height: diameter)
                        .rotationEffect(.degrees(shown * 360))
                }
            }
            .frame(width: diameter, height: diameter)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onAppear {
            if reduceMotion {
                shown = target
            } else {
                withAnimation(Tide.settle) { shown = target }
            }
        }
        .onChange(of: target) { _, new in
            withAnimation(reduceMotion ? nil : Tide.settle) { shown = new }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - TideStateMark

/// The hero of an empty or error state: a symbol tile inside two faint rings
/// and a soft glow that breathe slowly, so a screen with nothing on it still
/// feels alive. Reduce Motion holds it still.
struct TideStateMark: View {
    let systemName: String
    var tint: Color?
    var tileSize: CGFloat = Tide.tileLarge
    /// How far the halo reaches past the tile.
    var reach: CGFloat = Tide.stateHalo

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var breathe = false

    var body: some View {
        let color = tint ?? mood.accent
        let halo = tileSize + reach
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [color.opacity(0.24), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: halo / 2
                ))
                .opacity(breathe ? 1 : 0.55)
            Circle()
                .strokeBorder(color.opacity(0.10), lineWidth: 1)
                .scaleEffect(breathe ? 1 : 0.94)
                .opacity(breathe ? 0.4 : 1)
            Circle()
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
                .frame(width: halo * 0.72, height: halo * 0.72)
                .scaleEffect(breathe ? 1.05 : 1)
            TideIconTile(systemName: systemName, tint: color, size: tileSize)
        }
        .frame(width: halo, height: halo)
        // The glow is drawn past the layout box, so it never pushes content away.
        .frame(width: tileSize + reach / 2, height: tileSize + reach / 2)
        .animation(reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: breathe)
        .onAppear { breathe = true }
        .accessibilityHidden(true)
    }
}

// MARK: - TideDayBar

/// The 24 hours as one bar with a stretch of it lit: an eating window, a
/// night's sleep. Times are minutes after midnight; an `end` before the
/// `start` wraps past midnight.
struct TideDayBar: View {
    let start: Int
    let end: Int
    var color: Color?
    var height: CGFloat = Tide.s3

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private let day = 24.0 * 60

    var body: some View {
        let accent = color ?? mood.accent
        GeometryReader { proxy in
            let width = proxy.size.width
            let from = position(start, in: width)
            let to = position(end, in: width)
            ZStack(alignment: .leading) {
                Capsule().fill(Tide.fill)
                if end > start {
                    lit(from: from, to: to, accent)
                } else if end < start {
                    lit(from: from, to: width, accent)
                    lit(from: 0, to: to, accent)
                }
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : Tide.snap, value: start)
        .animation(reduceMotion ? nil : Tide.snap, value: end)
        .accessibilityHidden(true)
    }

    private func position(_ minutes: Int, in width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(Double(minutes), 0), day) / day)
    }

    private func lit(from: CGFloat, to: CGFloat, _ accent: Color) -> some View {
        Capsule()
            .fill(accent)
            .frame(width: max(to - from, 0))
            .offset(x: from)
            .shadow(color: accent.opacity(0.5), radius: Tide.s2)
    }
}
