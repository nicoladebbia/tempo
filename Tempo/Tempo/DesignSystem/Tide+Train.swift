//
// Tide+Train.swift
// Tempo
//
// Pieces of the Tide design system that only the Train area needs: the set
// stepper, the shader-lit rest ring, set strips, stat figures and row styles.
// Everything is namespaced `Train*` / `TideTrain` so it never collides with
// another area's additions.
//

import SwiftUI

// MARK: - TideTrain

enum TideTrain {
    /// Warnings, ramp sets, deload, "go easy".
    static let caution = Color(red: 1.00, green: 0.80, blue: 0.40)
    /// Done, on target, improving.
    static let positive = Color(red: 0.42, green: 0.94, blue: 0.66)
    /// A personal record.
    static let record = Color(red: 1.00, green: 0.84, blue: 0.30)
    /// A second data colour next to the mood accent.
    static let violet = Color(red: 0.72, green: 0.62, blue: 1.00)

    /// The tall primary button on the set logger.
    static let bigButton: CGFloat = 60
    /// The round +/- buttons next to a set figure.
    static let stepButton: CGFloat = 56
    /// Exercise picture sizes.
    static let thumb: CGFloat = 56
    static let hero: CGFloat = 168

    /// Condensed tabular figures that scale with Dynamic Type through a text
    /// style, for numbers that are not worth a `TideNumber`.
    static func figure(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, weight: weight).width(.condensed).monospacedDigit()
    }
}

// MARK: - TrainNumeralModifier

/// A big number in condensed tabular figures that still follows Dynamic Type,
/// and shrinks before it wraps (a long clock must stay on one line).
private struct TrainNumeralModifier: ViewModifier {
    @ScaledMetric
    private var size: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content
            .font(Tide.numeral(size, weight))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
    }
}

extension View {
    /// `size` is the point size at the default text size.
    func trainNumeral(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        modifier(TrainNumeralModifier(size: size, weight: weight, relativeTo: style))
    }
}

// MARK: - Sheets

/// The day's mood travels into the cover or sheet by hand: a presentation sits
/// above the shell, so the accent would otherwise fall back to neutral.
private struct TrainSheetRootModifier: ViewModifier {
    let energy: Double
    @Environment(ServiceContainer.self)
    private var services

    func body(content: Content) -> some View {
        let mood = TideMood(score: services.appState.dayScore)
        content
            .tidePage(energy: energy)
            .environment(\.tideInsidePage, false)
            .environment(\.tideMood, mood)
            .tint(mood.accent)
            // `Color.accentColor` in plain SwiftUI views only follows `.tint`
            // inside a UIKit container (a NavigationStack). A bare cover root
            // needs the accent set as well, or its labels stay system blue.
            .accentColor(mood.accent)
    }
}

extension View {
    /// The root of a sheet. A sheet opened from inside a page would otherwise
    /// inherit "this page already has a field" and show none.
    func trainSheetRoot(energy: Double = Tide.sheetEnergy) -> some View {
        modifier(TrainSheetRootModifier(energy: energy))
    }
}

// MARK: - TrainCardPressStyle

/// A card that dips under the finger. Used for rows that open a detail page.
struct TrainCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Tide.pressCard : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TrainCardPressStyle {
    static var trainCard: TrainCardPressStyle {
        TrainCardPressStyle()
    }
}

// MARK: - TrainHeader

/// The top of a tab home: a small label line, a big title, and round glass
/// buttons on the right.
struct TrainHeader<Trailing: View>: View {
    let label: String
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s2) {
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(label).tideLabel()
                Text(title)
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tide.s2)
            trailing
        }
    }
}

// MARK: - TrainIconButton

/// A round glass icon button (44 pt).
struct TrainIconButton: View {
    let systemImage: String
    let label: String
    var tint: Color = Tide.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Tide.bodyStrong)
                .foregroundStyle(tint)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - TrainMenuLabel

/// The glass circle that a `Menu` wears, so a menu button matches `TrainIconButton`.
struct TrainMenuLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
            .frame(width: Tide.hit, height: Tide.hit)
            .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
    }
}

// MARK: - TrainStat

/// A number with its small label under it: the unit of every summary row.
struct TrainStat: View {
    let value: String
    var unit: String?
    let label: String
    var size: CGFloat = 28
    var color: Color = Tide.text

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            TideNumber(value, unit: unit, size: size, relativeTo: .title, color: color)
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - TrainStatRow

/// A row of stats on one glass card, separated by thin lines.
struct TrainStatRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            content
        }
    }
}

// MARK: - TrainTag

/// A small tinted pill with an optional symbol ("Heavy", "Superset").
struct TrainTag: View {
    let text: String
    var systemImage: String?
    var color: Color = Tide.text2

    var body: some View {
        HStack(spacing: Tide.s1) {
            if let systemImage {
                Image(systemName: systemImage).font(Tide.label)
            }
            Text(text)
                .font(Tide.label)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Tide.s2)
        .padding(.vertical, Tide.s1)
        .background(color.opacity(0.16), in: .capsule)
    }
}

// MARK: - TrainRowLabel

/// A glass row that opens something: leading symbol, title, detail, chevron.
struct TrainRowLabel: View {
    let systemImage: String
    let title: String
    var detail: String?
    var tint: Color = Tide.text2

    var body: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: systemImage)
                .font(Tide.headline)
                .foregroundStyle(tint)
                .frame(width: Tide.icon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Tide.s2)
            Image(systemName: "chevron.right")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
    }
}

// MARK: - TrainStepper

/// One number of the set logger: a big condensed figure with round +/- buttons.
/// Tap the figure to type it. Holding a button repeats.
struct TrainStepper: View {
    @Binding var value: Double
    let label: String
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let unit: String
    var caption: String?
    var captionColor: Color = Tide.text2
    var onTapValue: (() -> Void)?

    @ScaledMetric(relativeTo: .largeTitle)
    private var figureSize: CGFloat = 68

    var body: some View {
        VStack(spacing: Tide.s2) {
            Text(label)
                .tideLabel()
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            HStack(spacing: Tide.s3) {
                stepButton("minus", "Decrease \(label.lowercased())", enabled: value > range.lowerBound) {
                    value = max(value - step, range.lowerBound)
                }
                figure
                stepButton("plus", "Increase \(label.lowercased())", enabled: value < range.upperBound) {
                    value = min(value + step, range.upperBound)
                }
            }
            if let caption {
                Text(caption)
                    .font(Tide.caption)
                    .foregroundStyle(captionColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    private var figure: some View {
        let content = VStack(spacing: Tide.hair) {
            Text(String(format: format, value))
                .font(Tide.numeral(figureSize))
                .foregroundStyle(Tide.text)
                .contentTransition(.numericText(value: value))
                .animation(Tide.snap, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text2)
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit)
        return Group {
            if let onTapValue {
                Button(action: onTapValue) { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Type a value")
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit)
        .accessibilityValue(String(format: format, value))
        .accessibilityAddTraits(onTapValue == nil ? [] : .isButton)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func stepButton(
        _ icon: String, _ name: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(Tide.headline)
                .foregroundStyle(enabled ? Tide.text : Tide.text3)
                .frame(width: TideTrain.stepButton, height: TideTrain.stepButton)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
        .accessibilityLabel(name)
    }
}

// MARK: - TrainSetStrip

/// Where you are in an exercise: one capsule per set. Done sets are lit, the
/// current one is wide and in the accent, ramp sets are outlined.
struct TrainSetStrip: View {
    struct Item: Identifiable {
        let id: UUID
        let done: Bool
        let current: Bool
        let warmup: Bool
    }

    let items: [Item]

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(spacing: Tide.s1) {
            ForEach(items) { item in
                Capsule()
                    .fill(fill(item))
                    .overlay {
                        if item.warmup, !item.done {
                            Capsule().strokeBorder(item.current ? mood.accent : Tide.text3, lineWidth: 1.5)
                        }
                    }
                    .frame(height: Tide.s2)
                    .frame(width: item.current ? nil : Tide.s6)
                    .frame(maxWidth: item.current ? .infinity : Tide.s6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Tide.snap, value: items.map { "\($0.done)\($0.current)" })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sets")
        .accessibilityValue("\(items.filter(\.done).count) of \(items.count) done")
    }

    private func fill(_ item: Item) -> AnyShapeStyle {
        if item.done {
            return AnyShapeStyle(TideTrain.positive)
        }
        if item.warmup {
            return AnyShapeStyle(Color.clear)
        }
        return item.current ? AnyShapeStyle(mood.accent) : AnyShapeStyle(Tide.fill)
    }
}

// MARK: - TrainRing

/// A shader-lit ring with a 60-tick scale. `progress` is how much of the ring
/// is lit; the content sits in the middle.
struct TrainRing<Content: View>: View {
    let progress: Double
    var tint: Color?
    var diameter: CGFloat = 264
    @ViewBuilder var content: Content

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        ZStack {
            TideClock { time in
                TrainRingFace(progress: min(max(progress, 0), 1), time: time, accent: tint ?? mood.accent)
            }
            content
                .padding(.horizontal, diameter * 0.2)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - TrainRingFace

private struct TrainRingFace: View, Animatable {
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

// MARK: - TrainEmptyCard

/// A calm card with one symbol and a few words: "nothing here yet".
struct TrainEmptyCard: View {
    let systemImage: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Tide.s3) {
            Image(systemName: systemImage)
                .font(Tide.title)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            Text(title)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .tideCard()
    }
}

// MARK: - Banners

/// A prompt card on Train home (missed session, welcome back, new week, venue
/// check, match found): a tinted label, a title, a line of help, then actions.
struct TrainBanner<Actions: View>: View {
    let systemImage: String
    let label: String
    var tint: Color = Color.accentColor
    var title: String?
    var message: String?
    private let actions: Actions

    init(
        systemImage: String,
        label: String,
        tint: Color = Color.accentColor,
        title: String? = nil,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.label = label
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s2) {
                Image(systemName: systemImage)
                    .font(Tide.caption)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(label).tideLabel(tint)
            }
            if title != nil || message != nil {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    if let title {
                        Text(title)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let message {
                        Text(message)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            actions
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }
}

/// A full-width pill inside a banner: filled in the banner's tint, or quiet.
struct TrainBannerButtonStyle: ButtonStyle {
    var tint: Color = Color.accentColor
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.bodyStrong)
            .foregroundStyle(filled ? Tide.ink : Tide.text)
            .padding(.horizontal, Tide.s4)
            .frame(maxWidth: .infinity, minHeight: Tide.hit)
            .background(filled ? tint : Tide.fill, in: .capsule)
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TrainBannerButtonStyle {
    static func trainBanner(tint: Color = Color.accentColor, filled: Bool = true) -> TrainBannerButtonStyle {
        TrainBannerButtonStyle(tint: tint, filled: filled)
    }
}

// MARK: - Filter chip

/// A selectable filter pill. 44pt tall to touch, accent when on.
struct TrainFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(Tide.bodyStrong)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Tide.ink : Tide.text2)
                .padding(.horizontal, Tide.s4)
                .frame(minHeight: Tide.hit)
                .background(isSelected ? Color.accentColor : Tide.fill, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(Tide.snap, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Glyph

/// A large symbol that still follows Dynamic Type.
private struct TrainGlyphModifier: ViewModifier {
    @ScaledMetric
    private var size: CGFloat

    init(size: CGFloat, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .semibold))
    }
}

extension View {
    func trainGlyph(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> some View {
        modifier(TrainGlyphModifier(size: size, relativeTo: style))
    }
}

// MARK: - Choice cell

/// One cell of a "pick one" grid (RPE, emphasis, weekday): 44pt tall, accent
/// when chosen, ink on the accent. The button's own action is untouched.
struct TrainChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Tide.ink : Tide.text)
            .frame(maxWidth: .infinity, minHeight: Tide.hit)
            .background(isSelected ? Color.accentColor : Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
            .contentShape(.rect(cornerRadius: Tide.controlRadius))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Tide.snap, value: isSelected)
            .sensoryFeedback(.selection, trigger: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension ButtonStyle where Self == TrainChoiceButtonStyle {
    static func trainChoice(isSelected: Bool) -> TrainChoiceButtonStyle {
        TrainChoiceButtonStyle(isSelected: isSelected)
    }
}

// MARK: - Rail button

/// One of a row of small glass actions, icon over a short caption (the guided
/// run's Pause / Skip rep / Add rep / Skip block). Four fit side by side.
struct TrainRailButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Tide.text : Tide.text3)
            .lineLimit(1)
            .minimumScaleFactor(Tide.labelShrink)
            .padding(.horizontal, Tide.s1)
            .frame(maxWidth: .infinity, minHeight: 56)
            .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .rect(cornerRadius: Tide.controlRadius))
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.rect(cornerRadius: Tide.controlRadius))
    }
}

extension ButtonStyle where Self == TrainRailButtonStyle {
    static var trainRail: TrainRailButtonStyle {
        TrainRailButtonStyle()
    }
}
