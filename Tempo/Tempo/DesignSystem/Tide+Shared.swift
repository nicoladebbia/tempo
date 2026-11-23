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
            .font(.system(size: size * 0.44 * scale, weight: .semibold))
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
