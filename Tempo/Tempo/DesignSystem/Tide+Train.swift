//
// Tide+Train.swift
// Tempo
//
// Pieces of the Tide design system that only the Train area needs: the set
// stepper, the shader-lit rest ring, set strips, stat figures and row styles.
// Everything is namespaced `Train*` / `TideTrain` so it never collides with
// another area's additions.
//

import Charts
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
    /// The ring on the monthly debrief, at the default text size.
    static let debriefRing: CGFloat = 120

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

// MARK: - TrainSheetRootModifier

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

// MARK: - TrainStatGrid

/// Stats side by side as far as they fit, one per row at accessibility text sizes
/// (a fixed minimum column would crowd three big numerals into one line).
struct TrainStatGrid<Content: View>: View {
    var minimum: CGFloat = TideTrain.statColumn
    var rowSpacing: CGFloat = Tide.s3
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        LazyVGrid(
            columns: typeSize.isAccessibilitySize
                ? [GridItem(.flexible(), alignment: .topLeading)]
                : [GridItem(.adaptive(minimum: minimum), spacing: Tide.s3, alignment: .topLeading)],
            alignment: .leading,
            spacing: rowSpacing
        ) {
            content
        }
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
    /// A long tag may run to several lines (at big text sizes) instead of being cut off.
    var wraps = false

    var body: some View {
        HStack(spacing: Tide.s1) {
            if let systemImage {
                Image(systemName: systemImage).font(Tide.label)
            }
            Text(text)
                .font(Tide.label)
                .lineLimit(wraps ? nil : 1)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: wraps)
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
        .accessibilityLabel(label)
        .accessibilityValue("\(String(format: format, value)) \(unit)")
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

// MARK: - TrainBanner

/// A prompt card on Train home (missed session, welcome back, new week, venue
/// check, match found): a tinted label, a title, a line of help, then actions.
struct TrainBanner<Actions: View>: View {
    let systemImage: String
    let label: String
    var tint: Color = .accentColor
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

// MARK: - TrainBannerButtonStyle

/// A full-width pill inside a banner: filled in the banner's tint, or quiet.
struct TrainBannerButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
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

// MARK: - TrainFilterChip

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

// MARK: - TrainGlyphModifier

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

// MARK: - TrainChoiceButtonStyle

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

// MARK: - TrainRailButtonStyle

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

// MARK: - Plan and progress kit (TrainPlan*)

// Pieces for the planning, program, library, history and progress screens:
// page and card shells, form fields, instrument charts and the week strip.
// Every size a screen needs lives here, so the views stay on tokens.

extension TideTrain {
    /// Space under the last card so the tab bar never covers it.
    static let pageBottom: CGFloat = 84
    /// A full trend chart, a small bar chart and the hero spark line.
    static let chartHeight: CGFloat = 188
    static let barsHeight: CGFloat = 124
    static let sparkHeight: CGFloat = 56
    /// A status dot next to a label.
    static let dot: CGFloat = 8
    /// The narrowest a stat cell gets before the grid wraps to a new row.
    static let statColumn: CGFloat = 96
    /// The widest the body figure on the Muscle Map is drawn.
    static let figureWidth: CGFloat = 176
    /// The widest a compact tab control is allowed to get.
    static let tabsCompact: CGFloat = 230
    /// The tall field of a multi-line text input.
    static let textArea: CGFloat = 140
    /// A small picture next to a row (library, picker, thumbnails in lists).
    static let rowThumb: CGFloat = 44
    /// The demo picture on an exercise page.
    static let demo: CGFloat = 200
    /// A round gauge (recovery ring) and the line it is drawn with.
    static let ring: CGFloat = 120
    static let ringInner: CGFloat = 96
    static let ringStroke: CGFloat = 10
    /// The half-circle gauge (strain) box.
    static let gaugeWidth: CGFloat = 160
    static let gaugeHeight: CGFloat = 80
    /// A single stacked bar (sleep stages).
    static let stackBar: CGFloat = 24
}

// MARK: - TrainPlanPage

/// The scroll shell of a plan screen: edge padding and room for the tab bar.
struct TrainPlanPage<Content: View>: View {
    var spacing: CGFloat = Tide.s4
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: spacing) {
                content
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, TideTrain.pageBottom)
        }
    }
}

// MARK: - TrainPlanCard

/// A glass card with an optional small label (and a value on the right).
struct TrainPlanCard<Content: View>: View {
    var label: String?
    var trailing: String?
    var padding: CGFloat = Tide.s4
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            if let label {
                TideSectionLabel(title: label, trailing: trailing)
            }
            content
        }
        .tideCard(padding: padding, radius: Tide.tileRadius)
    }
}

// MARK: - TrainPlanTabs

/// A glass segmented control. Equal-width segments while they fit, a sliding
/// row once the text gets large.
struct TrainPlanTabs<Tag: Hashable>: View {
    let items: [(tag: Tag, label: String)]
    @Binding var selection: Tag

    @Namespace
    private var slider

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(fill: true)
            ScrollView(.horizontal, showsIndicators: false) {
                row(fill: false)
            }
        }
        .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
        .animation(Tide.snap, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(fill: Bool) -> some View {
        HStack(spacing: Tide.hair) {
            ForEach(items, id: \.tag) { item in
                let on = item.tag == selection
                Button {
                    selection = item.tag
                } label: {
                    Text(item.label)
                        .font(items.count > 4 ? Tide.caption.weight(.semibold) : Tide.bodyStrong)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                        .foregroundStyle(on ? Tide.ink : Tide.text2)
                        .padding(.horizontal, fill ? Tide.s1 : Tide.s3)
                        .frame(maxWidth: fill ? .infinity : nil, minHeight: Tide.hit)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "slider", in: slider)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(Tide.s1)
    }
}

// MARK: - TrainPlanField

/// A labelled input: small caps label, the Tide field surface, an optional hint.
struct TrainPlanField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(label).tideLabel()
            content
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .tideFieldSurface()
            if let hint {
                Text(hint)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - TrainPlanToggleRow

/// A switch with a title and an optional line of help.
struct TrainPlanToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
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
        }
        .tint(Color.accentColor)
        .frame(minHeight: Tide.hit)
        .accessibilityLabel(title)
        .accessibilityHint(detail ?? "")
    }
}

// MARK: - TrainPlanPickerRow

/// A title on the left and a menu picker on the right; help text underneath.
/// Under accessibility text sizes the picker drops below the title.
struct TrainPlanPickerRow<Selection: Hashable, Options: View>: View {
    let title: String
    var detail: String?
    /// Long titles or long option names: the menu sits under the title.
    var stacked = false
    @Binding var selection: Selection
    @ViewBuilder var options: Options

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            let stack = stacked || typeSize.isAccessibilitySize
            let layout = stack
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                : AnyLayout(HStackLayout(spacing: Tide.s2))
            layout {
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !stack {
                    Spacer(minLength: Tide.s2)
                }
                Picker(title, selection: $selection) {
                    options
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Color.accentColor)
                .fixedSize()
            }
            .frame(minHeight: Tide.hit)
            if let detail {
                Text(detail)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - TrainPlanSearchField

/// The search box of a list: glass pill, magnifier, clear button.
struct TrainPlanSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: Tide.s2) {
            Image(systemName: "magnifyingglass")
                .font(Tide.body)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text3)
                        .frame(width: Tide.hit, height: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Tide.s4)
        .frame(minHeight: Tide.hit)
        .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
    }
}

// MARK: - TrainPlanDelta

/// "up 12% vs last week": an arrow and a percentage in the good or caution colour.
struct TrainPlanDelta: View {
    let fraction: Double
    let suffix: String

    var body: some View {
        let up = fraction >= 0
        HStack(spacing: Tide.hair) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(Tide.label)
            Text("\(abs(Int((fraction * 100).rounded())))% \(suffix)")
                .font(Tide.caption)
        }
        .foregroundStyle(up ? TideTrain.positive : TideTrain.caution)
        .lineLimit(1)
        .minimumScaleFactor(Tide.labelShrink)
    }
}

// MARK: - TrainPlanMeterRow

/// A label and a value over a thin level bar: muscle shares, ratios, compliance.
struct TrainPlanMeterRow: View {
    let label: String
    let value: String
    let fraction: Double
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(label)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                Spacer(minLength: Tide.s2)
                Text(value)
                    .font(TideTrain.figure(.footnote, weight: .semibold))
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
            }
            TideLevelBar(progress: max(fraction, 0.02), color: tint, height: Tide.bar)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

// MARK: - TrainPlanPoint

/// One point of a trend or bar series.
struct TrainPlanPoint: Identifiable {
    let date: Date
    let value: Double
    var isRecord = false

    var id: String {
        "\(date.timeIntervalSinceReferenceDate)|\(value)"
    }
}

// MARK: - TrainPlanAxis

/// Axis styling shared by every plan chart: hairline dotted rules, condensed
/// numerals, nothing else.
private enum TrainPlanAxis {
    static let rule = StrokeStyle(lineWidth: 0.5, dash: [2, 4])
    static var label: Font {
        TideTrain.figure(.caption2, weight: .medium)
    }
}

// MARK: - TrainPlanTrendChart

/// A scrubbable trend: soft area, a crisp line, a beacon on the latest value,
/// stars on records, an optional dashed comparison and a rule under the finger.
struct TrainPlanTrendChart: View {
    let points: [TrainPlanPoint]
    var ghost: [TrainPlanPoint] = []
    var tint: Color?
    @Binding var scrub: Date?

    @Environment(\.tideMood)
    private var mood

    private var domain: ClosedRange<Double> {
        let values = (points + ghost).map(\.value)
        guard let low = values.min(), let high = values.max() else {
            return 0 ... 1
        }
        let pad = max((high - low) * 0.2, high * 0.02, 1)
        return max(0, low - pad) ... (high + pad)
    }

    private var nearest: TrainPlanPoint? {
        guard let scrub else {
            return nil
        }
        return points.min { abs($0.date.timeIntervalSince(scrub)) < abs($1.date.timeIntervalSince(scrub)) }
    }

    var body: some View {
        let accent = tint ?? mood.accent
        let range = domain
        let selected = nearest
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", range.lowerBound),
                    yEnd: .value("Value", point.value)
                )
                .foregroundStyle(LinearGradient(
                    colors: [accent.opacity(0.34), accent.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)

                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }

            if points.count <= 14 {
                ForEach(points) { point in
                    PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                        .symbolSize(22)
                        .foregroundStyle(accent)
                }
            }

            ForEach(points.filter(\.isRecord)) { point in
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .symbol {
                        Image(systemName: "star.fill")
                            .font(Tide.label)
                            .foregroundStyle(TideTrain.record)
                    }
            }

            ForEach(ghost) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Compare", point.value),
                    series: .value("Series", "compare")
                )
                .foregroundStyle(TideTrain.violet.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .interpolationMethod(.monotone)
            }

            if let last = points.last, selected == nil {
                PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                    .symbolSize(240)
                    .foregroundStyle(accent.opacity(0.22))
                PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                    .symbolSize(54)
                    .foregroundStyle(accent)
            }

            if let selected {
                RuleMark(x: .value("Scrub", selected.date))
                    .foregroundStyle(Tide.text3)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Scrub", selected.date), y: .value("Value", selected.value))
                    .symbolSize(120)
                    .foregroundStyle(accent)
            }
        }
        .chartXSelection(value: $scrub)
        .chartYScale(domain: range)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine(stroke: TrainPlanAxis.rule).foregroundStyle(Tide.hairline)
                AxisValueLabel().font(TrainPlanAxis.label).foregroundStyle(Tide.text3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(TrainPlanAxis.label)
                    .foregroundStyle(Tide.text3)
            }
        }
        // Axis labels stop growing at xxxLarge: past that they overlap on a phone.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: TideTrain.chartHeight)
    }
}

// MARK: - TrainPlanSpark

/// A small, axis-free area line: the shape of the last few weeks at a glance.
struct TrainPlanSpark: View {
    let values: [Double]
    var tint: Color?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        let accent = tint ?? mood.accent
        let top = max(values.max() ?? 1, 1)
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            AreaMark(x: .value("Step", index), yStart: .value("Base", 0), yEnd: .value("Value", value))
                .foregroundStyle(LinearGradient(
                    colors: [accent.opacity(0.32), accent.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Step", index), y: .value("Value", value))
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            if index == values.count - 1 {
                PointMark(x: .value("Step", index), y: .value("Value", value))
                    .symbolSize(60)
                    .foregroundStyle(accent)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... top * 1.15)
        .frame(height: TideTrain.sparkHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - TrainPlanBarChart

/// Labelled bars with an optional dashed average. The newest bar is lit, the
/// others sit back.
struct TrainPlanBarChart: View {
    struct Bar: Identifiable {
        let id: String
        let label: String
        let value: Double
    }

    let bars: [Bar]
    var average: Double?
    var tint: Color?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        let accent = tint ?? mood.accent
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Week", bar.label), y: .value("Count", bar.value), width: .ratio(0.62))
                    .foregroundStyle(bar.id == bars.last?.id ? accent : accent.opacity(0.5))
                    .clipShape(.rect(cornerRadius: Tide.s1))
            }
            if let average, average > 0 {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Tide.text3)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine(stroke: TrainPlanAxis.rule).foregroundStyle(Tide.hairline)
                AxisValueLabel().font(TrainPlanAxis.label).foregroundStyle(Tide.text3)
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisValueLabel().font(TrainPlanAxis.label).foregroundStyle(Tide.text3)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: TideTrain.barsHeight)
    }
}

// MARK: - TrainPlanDateBars

/// Thin capsule bars along a date axis (one per session); the scrubbed one is lit.
struct TrainPlanDateBars: View {
    let points: [TrainPlanPoint]
    var highlight: Date?
    var tint: Color?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        let accent = tint ?? mood.accent
        Chart(points) { point in
            BarMark(x: .value("Date", point.date), y: .value("Volume", point.value), width: .fixed(6))
                .foregroundStyle(point.date == highlight ? accent : accent.opacity(0.55))
                .clipShape(Capsule())
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) {
                AxisValueLabel().font(TrainPlanAxis.label).foregroundStyle(Tide.text3)
            }
        }
        .chartXAxis(.hidden)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: TideTrain.barsHeight * 0.72)
    }
}

// MARK: - TrainPlanWeekStrip

/// Seven columns for a training week: a load bar on top, then the weekday, the
/// session code and a status mark. Drag across it to read any day.
struct TrainPlanWeekStrip: View {
    struct Day: Identifiable {
        let id: Int
        let weekday: String
        var code: String?
        var extra: String?
        /// 0 ... 1 against the busiest day; 0 shows a short stub.
        var load: Double = 0
        var barColor: Color = Tide.text3
        var isToday = false
        var isDone = false
        var isMatch = false
    }

    let days: [Day]
    var selected: Int?
    let onScrub: (Int) -> Void
    let onRelease: (_ index: Int, _ travel: CGFloat) -> Void

    @Environment(\.tideMood)
    private var mood

    private static let barSpace: CGFloat = 76
    private static let barWidth: CGFloat = 20
    private static let stub: CGFloat = 6
    private static let inset = Tide.s1

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(days) { day in
                column(day)
            }
        }
        // Seven columns cannot grow with the text; the day cards below carry
        // the same information at any size.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .padding(Self.inset)
        .tideCard(padding: 0, radius: Tide.tileRadius)
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(drag(width: geo.size.width))
            }
        }
        .animation(Tide.lively, value: selected)
        // One adjustable element: swipe up or down to step through the week,
        // which runs the same code as dragging a finger across the columns.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training week")
        .accessibilityValue(spokenValue)
        .accessibilityHint("Swipe up or down to read each day.")
        .accessibilityAdjustableAction { direction in
            let current = selected ?? (direction == .increment ? -1 : days.count)
            let next = direction == .increment ? current + 1 : current - 1
            guard days.indices.contains(next) else {
                return
            }
            onScrub(next)
            // A large travel keeps the release from reading as a tap that
            // closes the day again.
            onRelease(next, Self.stepTravel)
        }
    }

    /// Distance reported with an accessibility step so it never counts as a tap.
    private static let stepTravel: CGFloat = 100

    private var spokenValue: String {
        guard let selected, let day = days.first(where: { $0.id == selected }) else {
            return "No day selected"
        }
        var parts = [day.weekday]
        parts.append(day.code ?? "no session")
        if let extra = day.extra {
            parts.append(extra)
        }
        if day.isToday {
            parts.append("today")
        }
        if day.isDone {
            parts.append("done")
        } else if day.isMatch {
            parts.append("match")
        }
        return parts.joined(separator: ", ")
    }

    private func index(at x: CGFloat, width: CGFloat) -> Int {
        let slot = max((width - Self.inset * 2) / CGFloat(max(days.count, 1)), 1)
        return min(max(Int((x - Self.inset) / slot), 0), max(days.count - 1, 0))
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onScrub(index(at: value.location.x, width: width))
            }
            .onEnded { value in
                onRelease(index(at: value.location.x, width: width), abs(value.translation.width))
            }
    }

    private func column(_ day: Day) -> some View {
        let on = selected == day.id
        let height = day.load > 0 ? Self.stub + (Self.barSpace - Self.stub) * min(day.load, 1) : Self.stub
        return VStack(spacing: Tide.s1) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: Self.barSpace)
                Capsule()
                    .fill(day.barColor)
                    .frame(width: Self.barWidth, height: height)
                    .overlay {
                        Capsule().strokeBorder(on ? Tide.text : Color.clear, lineWidth: Tide.focusLine)
                    }
                    .scaleEffect(on ? 1.1 : 1, anchor: .bottom)
            }
            Text(day.weekday)
                .font(Tide.label)
                .foregroundStyle(day.isToday ? mood.accent : Tide.text3)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            Text(day.code ?? "-")
                .font(TideTrain.figure(.caption, weight: .semibold))
                .foregroundStyle(day.code == nil ? Tide.text3 : Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            Text(day.extra ?? " ")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            statusMark(day)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tide.s2)
        .background(day.isToday ? Tide.fill : Color.clear, in: .rect(cornerRadius: Tide.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                .strokeBorder(day.isToday ? mood.accent : Color.clear, lineWidth: Tide.focusLine)
        }
    }

    private func statusMark(_ day: Day) -> some View {
        Group {
            if day.isDone {
                Image(systemName: "checkmark").foregroundStyle(TideTrain.positive)
            } else if day.isMatch {
                Image(systemName: "sportscourt").foregroundStyle(Tide.text2)
            } else {
                Color.clear
            }
        }
        .font(Tide.label)
        .frame(height: Tide.s3)
    }
}

// MARK: - TrainPlanCell

extension View {
    /// A compact input cell for dense editors: soft fill, hairline, 44 pt tall.
    func trainPlanCell() -> some View {
        let shape = RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
        return padding(.horizontal, Tide.s3)
            .frame(minHeight: Tide.hit)
            .background(Tide.fill, in: shape)
            .overlay(shape.strokeBorder(Tide.hairline, lineWidth: 1))
    }
}

// MARK: - TrainPlanCellField

/// A small label over a compact input cell: the unit of a dense editor row.
struct TrainPlanCellField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            content
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .trainPlanCell()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - TrainPlanFieldRow

/// Fields side by side while they fit, stacked once they do not.
struct TrainPlanFieldRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Tide.s2) {
                content
            }
            VStack(spacing: Tide.s2) {
                content
            }
        }
    }
}

// MARK: - TrainPlanAddButton

/// "+ Add day": a quiet full-width glass button for adding a row to a list.
struct TrainPlanAddButton: View {
    let title: String
    var systemImage = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Tide.bodyStrong)
                .foregroundStyle(Color.accentColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TrainPlanDivider

/// A hairline between rows inside a card.
struct TrainPlanDivider: View {
    var body: some View {
        Rectangle()
            .fill(Tide.hairline)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - TrainPlanListRow

extension View {
    /// A transparent list row that carries its own glass card, edge to edge.
    /// For lists that must stay a `List` (swipe actions, delete, reorder).
    func trainPlanListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: Tide.s1, leading: Tide.edge, bottom: Tide.s1, trailing: Tide.edge))
    }
}

// MARK: - TrainPlanSecondaryButtonStyle

/// The quiet glass button, like `.tempoSecondary`, but the label may wrap onto
/// a second line instead of shrinking and cutting off at large text sizes.
struct TrainPlanSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.headline)
            .foregroundStyle(isEnabled ? Tide.text : Tide.text3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Tide.s5)
            .padding(.vertical, Tide.s2)
            .frame(maxWidth: .infinity, minHeight: Tide.fieldHeight)
            .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
            .scaleEffect(configuration.isPressed ? Tide.pressButton : 1)
            .animation(Tide.snap, value: configuration.isPressed)
            .contentShape(.capsule)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension ButtonStyle where Self == TrainPlanSecondaryButtonStyle {
    static var trainPlanSecondary: TrainPlanSecondaryButtonStyle {
        TrainPlanSecondaryButtonStyle()
    }
}
