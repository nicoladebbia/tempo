//
// TideWidgetKit.swift
// TempoWidget
//
// The Tide look for widgets and Live Activities. The tokens themselves
// (`Tide`, `TideMood`) are the app's own files, compiled into this target
// (see project.yml), so a colour or a size changes in one place. What lives
// here is only what the app draws with Metal shaders, redrawn with plain
// shapes because an extension cannot run them: the ticked dial, the level bar,
// the glow field behind a widget.
//

import SwiftUI
import WidgetKit

// MARK: - TideWidgetBackground

/// The field behind a widget: the ink, lit by the day's mood from two corners.
struct TideWidgetBackground: View {
    let mood: TideMood

    var body: some View {
        ZStack {
            Tide.ink
            RadialGradient(
                colors: [mood.glowA.opacity(0.9), .clear],
                center: .topLeading, startRadius: 0, endRadius: 230
            )
            RadialGradient(
                colors: [mood.glowB.opacity(0.75), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 210
            )
        }
    }
}

extension View {
    /// The widget's background, in the day's mood.
    func tideWidgetContainer(_ mood: TideMood) -> some View {
        containerBackground(for: .widget) { TideWidgetBackground(mood: mood) }
    }
}

// MARK: - WidgetLabel

/// Small tracked capitals, like `TideLabel` in the app.
struct WidgetLabel: View {
    let text: String
    var color: Color = Tide.text2

    init(_ text: String, color: Color = Tide.text2) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Tide.label)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(Tide.labelShrink)
            .accessibilityLabel(text)
    }
}

// MARK: - WidgetFigure

/// A figure in the app's condensed tabular numerals, with an optional unit.
struct WidgetFigure: View {
    let value: String
    var unit: String?
    var size: CGFloat = Tide.numeralM
    var color: Color = Tide.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
            Text(value)
                .font(Tide.numeral(size))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.system(size: max(11, size * 0.42), weight: .semibold))
                    .foregroundStyle(Tide.text2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - WidgetDial

/// The score dial: a 60-tick scale whose light grows with the value.
struct WidgetDial: View {
    /// 0...1, nil draws an unlit scale.
    let progress: Double?
    let accent: Color
    /// Length of an ordinary tick; every fifth is longer.
    var tick: CGFloat = 5

    private let count = 60

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            let lit = Int(((progress ?? 0) * Double(count)).rounded())
            for index in 0 ..< count {
                let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
                let length = index % 5 == 0 ? tick * 1.7 : tick
                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + cos(angle) * (outer - length),
                    y: center.y + sin(angle) * (outer - length)
                ))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                let isLit = index < lit
                if isLit {
                    // A soft glow under the lit ticks, brighter toward the head.
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: accent.opacity(0.55), radius: 3))
                        layer.stroke(
                            path,
                            with: .color(accent.opacity(0.55 + 0.45 * Double(index) / Double(max(lit, 1)))),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                    }
                } else {
                    context.stroke(path, with: .color(Tide.hairline), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - WidgetRing

/// A progress ring with a soft glow and a bright head, for a goal that carries
/// its own colour (water, calories). The caller puts any text in the middle.
struct WidgetRing: View {
    /// 0...1, nil draws an empty track.
    let progress: Double?
    let color: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        let shown = min(max(progress ?? 0, 0), 1)
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radius = (diameter - lineWidth) / 2
            ZStack {
                Circle()
                    .stroke(Tide.hairline, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if shown > 0 {
                    Circle()
                        .trim(from: 0, to: shown)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: color.opacity(0.5), radius: lineWidth * 0.8)
                    if shown < 0.995 {
                        Circle()
                            .fill(Tide.text.opacity(0.9))
                            .frame(width: lineWidth * 0.42, height: lineWidth * 0.42)
                            .offset(y: -radius)
                            .frame(width: diameter, height: diameter)
                            .rotationEffect(.degrees(shown * 360))
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - WidgetBar

/// A progress bar with a soft glow on its lit part.
struct WidgetBar: View {
    /// 0...1, nil draws an empty track.
    let progress: Double?
    let color: Color
    var height: CGFloat = Tide.bar

    var body: some View {
        GeometryReader { proxy in
            let lit = max(proxy.size.width * (progress ?? 0), progress == nil ? 0 : height)
            ZStack(alignment: .leading) {
                Capsule().fill(Tide.hairline)
                if progress != nil {
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: lit)
                        .shadow(color: color.opacity(0.5), radius: 3)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - WidgetEmptyState

/// What a widget shows before the app has written anything for it.
struct WidgetEmptyState: View {
    let symbol: String
    let title: String
    var hint: String = "Open Tempo to set up your day."
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 18 : 24, weight: .semibold))
                .foregroundStyle(TideMood.neutral.accent)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(title)
                .font(compact ? Tide.bodyStrong : Tide.headline)
                .foregroundStyle(Tide.text)
            Text(hint)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(compact ? 2 : 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
