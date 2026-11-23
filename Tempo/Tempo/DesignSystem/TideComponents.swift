//
// TideComponents.swift
// Tempo
//
// The building blocks every rebuilt screen is made of.
//

import SwiftUI

// MARK: - Background

/// The living background. One per screen, behind everything.
struct TideBackground: View {
    /// 0...1: how much colour the field carries. Detail pages can turn it down.
    var energy: Double = 1.0
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        TideClock { time in
            Rectangle()
                .fill(Tide.ink)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.tideField(
                        .float2(proxy.size), .float(time),
                        .color(Tide.ink), .color(mood.glowA), .color(mood.glowB), .color(mood.ember),
                        .float(energy)
                    ))
                }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces and labels

extension View {
    /// A floating glass surface. The ink tint keeps white text readable whatever is behind it.
    func tideCard(padding: CGFloat = Tide.s5, radius: CGFloat = Tide.cardRadius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Tide.ink.opacity(0.34)), in: .rect(cornerRadius: radius))
    }

    /// Small tracked capitals for section and field labels.
    func tideLabel(_ color: Color = Tide.text2) -> some View {
        font(Tide.label).tracking(1.1).textCase(.uppercase).foregroundStyle(color)
    }
}

/// A section heading with an optional trailing value.
struct TideSectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).tideLabel()
            Spacer(minLength: Tide.s2)
            if let trailing {
                Text(trailing).font(Tide.caption).foregroundStyle(Tide.text2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Numbers

/// A number in the app's condensed tabular figures, with an optional unit.
/// Scales with Dynamic Type and animates digit changes.
struct TideNumber: View {
    let value: String
    var unit: String?
    var weight: Font.Weight = .bold
    var color: Color = Tide.text

    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var unitSize: CGFloat

    init(
        _ value: String, unit: String? = nil, size: CGFloat = 28,
        relativeTo style: Font.TextStyle = .title, weight: Font.Weight = .bold, color: Color = Tide.text
    ) {
        self.value = value
        self.unit = unit
        self.weight = weight
        self.color = color
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        _unitSize = ScaledMetric(wrappedValue: max(11, size * 0.42), relativeTo: style)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
            Text(value)
                .font(Tide.numeral(size, weight))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.system(size: unitSize, weight: .semibold))
                    .foregroundStyle(Tide.text2)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dial

/// The score dial: a shader-drawn ring with a 60-tick scale whose light grows
/// with the value, and the number inside it.
struct TideDial: View {
    /// 0...100, nil when there is no score.
    let score: Int?
    var caption: String = "Day score"
    var diameter: CGFloat = 220

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var shown: Double = 0

    private var target: Double { Double(min(max(score ?? 0, 0), 100)) / 100 }

    var body: some View {
        ZStack {
            TideClock { time in
                TideDialFace(progress: shown, time: time, accent: mood.accent)
            }
            VStack(spacing: Tide.s1) {
                TideNumber(score.map(String.init) ?? "--", size: diameter * 0.36, relativeTo: .largeTitle)
                Text(caption).tideLabel()
            }
            .padding(.horizontal, diameter * 0.2)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { shown = target } else { withAnimation(Tide.settle) { shown = target } }
        }
        .onChange(of: target) { _, new in
            withAnimation(reduceMotion ? nil : Tide.settle) { shown = new }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(score.map { "\($0) out of 100" } ?? "No score yet")
    }
}

private struct TideDialFace: View, Animatable {
    var progress: Double
    var time: Double
    var accent: Color

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = progress, t = time, accent = accent
        Rectangle().fill(.white)
            .visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.tideDial(.float2(proxy.size), .float(p), .float(t), .color(accent)))
            }
    }
}

// MARK: - Level bar

/// A shader-lit progress bar with a hot leading edge. Colour defaults to the mood accent.
struct TideLevelBar: View, Animatable {
    var progress: Double
    var color: Color?
    var height: CGFloat = 6

    @Environment(\.tideMood)
    private var mood

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = progress, accent = color ?? mood.accent
        Capsule().fill(.white)
            .frame(height: height)
            .visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.tideLevel(.float2(proxy.size), .float(p), .color(accent)))
            }
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
    }
}

// MARK: - Controls

/// The one filled button per screen: the next thing to do.
struct TidePrimaryButtonStyle: ButtonStyle {
    @Environment(\.tideMood)
    private var mood
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.headline)
            .foregroundStyle(Tide.ink)
            .padding(.horizontal, Tide.s5)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(mood.accent.opacity(isEnabled ? 1 : 0.4), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.capsule)
    }
}

/// Secondary actions: interactive glass.
struct TideGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
            .padding(.horizontal, Tide.s4)
            .frame(minWidth: Tide.hit, minHeight: Tide.hit)
            .glassEffect(.regular.interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TidePrimaryButtonStyle {
    static var tidePrimary: TidePrimaryButtonStyle { TidePrimaryButtonStyle() }
}

extension ButtonStyle where Self == TideGlassButtonStyle {
    static var tideGlass: TideGlassButtonStyle { TideGlassButtonStyle() }
}

/// A small tappable pill ("+ Banana", a filter).
struct TideChip: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tide.s2) {
                if let systemImage {
                    Image(systemName: systemImage).font(Tide.caption)
                }
                Text(title).font(Tide.bodyStrong).lineLimit(1)
            }
            .foregroundStyle(Tide.text)
            .padding(.horizontal, Tide.s4)
            .frame(minHeight: Tide.hit)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
