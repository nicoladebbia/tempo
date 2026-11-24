//
// Tide+TrainSession.swift
// Tempo
//
// Pieces for everything the user sees while doing or finishing a workout: the
// set logger's hero card, the session clock bar, the rest and state screens,
// a "pick one" row and a sheet section. All names start with `TrainSession`
// so they never collide with another area's additions. Uses `Tide+Train.swift`
// (read-only) for the shared Train pieces.
//

import SwiftUI

// MARK: - TideTrainSession

enum TideTrainSession {
    /// The weight and reps figures on the set card, at the default text size.
    static let figure: CGFloat = 54
    /// The session clock in the bar above the logger.
    static let clock: CGFloat = 30
    /// The rest ring: full, and when the "how was that set" card shares the page.
    static let restRing: CGFloat = 248
    static let restRingCompact: CGFloat = 200
    /// The rest countdown inside that ring, at the default text size.
    static let restClock: CGFloat = 64
    /// The most the clock grows with the text size: it has to stay inside its ring.
    static let restClockCap: CGFloat = 84
    /// The 3-2-1 before a guided run, inside its ring.
    static let countdownFigure: CGFloat = 120
    /// The completion ring on the summary.
    static let summaryRing: CGFloat = 176
    /// The countdown figure on a live screen, at the default text size.
    static let bigClock: CGFloat = 88
    /// The clock inside a ring, and the figure on a state screen.
    static let ringClock: CGFloat = 56
    static let stateFigure: CGFloat = 52
    /// A big symbol on a state screen, and the tile behind it.
    static let stateGlyph: CGFloat = 36
    static let stateTile: CGFloat = 88
    /// A pick-one cell that is taller than a standard control (RPE).
    static let choiceHeight: CGFloat = 52
    /// A slim vertical rule between two columns.
    static let rule: CGFloat = 1
    /// One dot of a step trail, and the long one that is "now".
    static let dot: CGFloat = 8
    /// The line that joins the cards of a superset.
    static let rail: CGFloat = 2
    /// How strong a tinted outline is drawn.
    static let outlineOpacity = 0.4
    /// A small number field beside its label (minutes, metres, rounds).
    static let fieldWidth: CGFloat = 100
    /// A short label column ("Rep 3", "KM 12") so every field beside it starts at the same edge.
    static let repLabel: CGFloat = 52
    /// How far a clock numeral may shrink before it truncates.
    static let clockShrink: CGFloat = 0.5
    /// The training-load chart: plot height, and the empty-state height it keeps.
    static let chartHeight: CGFloat = 140
    static let chartEmptyHeight: CGFloat = 80
    /// Chart marks: the sweet-spot band, the injury limit line, the grid.
    static let zoneBandOpacity = 0.12
    static let limitLineOpacity = 0.6
    static let gridOpacity = 0.2
    static let limitDash: [CGFloat] = [4, 3]
}

extension View {
    /// A thin tinted outline that marks a card as special (a record, a superset).
    func trainSessionOutline(_ color: Color, radius: CGFloat = Tide.tileRadius) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color.opacity(TideTrainSession.outlineOpacity), lineWidth: TideTrainSession.rule)
        )
    }
}

// MARK: - TrainSessionBar

/// The strip above the logger: the clock as the hero, sets and volume as small
/// read-outs, and a lit bar for how much of the session is done.
struct TrainSessionBar: View {
    let elapsed: String
    let done: Int
    let total: Int
    let volume: String

    @ScaledMetric(relativeTo: .title)
    private var clockSize: CGFloat = TideTrainSession.clock
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var fraction: Double {
        Double(done) / Double(max(1, total))
    }

    var body: some View {
        VStack(spacing: Tide.s2) {
            layout {
                Text(elapsed)
                    .font(Tide.numeral(clockSize))
                    .foregroundStyle(Tide.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)
                }
                HStack(spacing: Tide.s5) {
                    readout("Sets", "\(done)/\(total)")
                    readout("Volume", volume)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TideLevelBar(progress: fraction, height: Tide.barSlim)
                .animation(Tide.snap, value: fraction)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.vertical, Tide.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout time \(elapsed), \(done) of \(total) sets, volume \(volume)")
    }

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: Tide.s3))
    }

    private func readout(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: Tide.hair) {
            Text(value)
                .font(TideTrain.figure(.subheadline, weight: .semibold))
                .foregroundStyle(Tide.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).tideLabel(Tide.text3)
        }
    }
}

// MARK: - TrainSessionField

/// One of the two numbers on the set card: label, big figure, unit and the
/// round -/+ buttons. Tap the figure to type it. Holding a button repeats.
struct TrainSessionField: View {
    @Binding
    var value: Double
    let label: String
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let unit: String
    /// True in the two-column layout, so both labels take the same height and
    /// the figures line up.
    var reserveLabel = false
    var onTapValue: (() -> Void)?

    @ScaledMetric(relativeTo: .largeTitle)
    private var figureSize: CGFloat = TideTrainSession.figure

    var body: some View {
        VStack(spacing: Tide.s2) {
            Text(label)
                .tideLabel()
                .lineLimit(2, reservesSpace: reserveLabel)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(Tide.labelShrink)
            figure
            HStack(spacing: Tide.s3) {
                stepButton("minus", "Decrease \(label.lowercased())", enabled: value > range.lowerBound) {
                    value = max(value - step, range.lowerBound)
                }
                stepButton("plus", "Increase \(label.lowercased())", enabled: value < range.upperBound) {
                    value = min(value + step, range.upperBound)
                }
            }
        }
        .frame(maxWidth: .infinity)
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
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit)
        .contentShape(.rect)
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

// MARK: - TrainSessionSetCard

/// The hero of the logger: the two numbers of the current set side by side
/// (stacked at accessibility text sizes), their hints under them, and one
/// footer line of context (last time, target, best).
struct TrainSessionSetCard<Primary: View, Secondary: View, Hints: View, Footer: View>: View {
    private let primary: Primary
    private let secondary: Secondary
    private let hints: Hints
    private let footer: Footer
    private let showsHints: Bool

    @Environment(\.dynamicTypeSize)
    private var typeSize

    init(
        showsHints: Bool = true,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary,
        @ViewBuilder hints: () -> Hints,
        @ViewBuilder footer: () -> Footer
    ) {
        self.primary = primary()
        self.secondary = secondary()
        self.hints = hints()
        self.footer = footer()
        self.showsHints = showsHints
    }

    var body: some View {
        VStack(spacing: Tide.s4) {
            if typeSize.isAccessibilitySize {
                VStack(spacing: Tide.s5) {
                    primary
                    secondary
                }
            } else {
                HStack(alignment: .top, spacing: Tide.s3) {
                    primary
                    Rectangle()
                        .fill(Tide.hairline)
                        .frame(width: TideTrainSession.rule)
                        .padding(.vertical, Tide.s2)
                        .accessibilityHidden(true)
                    secondary
                }
            }
            if showsHints {
                VStack(spacing: Tide.s1) {
                    hints
                }
            }
            TrainSessionRule()
            footer
        }
        .tideCard(padding: Tide.s4)
    }
}

// MARK: - TrainSessionContext

/// Last time, today's target and the best ever, on one line of three cells.
struct TrainSessionContext: View {
    struct Cell: Identifiable {
        let label: String
        let value: String
        var highlight = false
        var id: String {
            label
        }
    }

    let cells: [Cell]

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        layout {
            ForEach(cells) { cell in
                VStack(spacing: Tide.hair) {
                    Text(cell.value)
                        .font(TideTrain.figure(.headline))
                        .foregroundStyle(cell.highlight ? mood.accent : Tide.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                    Text(cell.label).tideLabel()
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - TrainSessionStateView

/// A calm full-page state with one symbol, a few words and the next actions:
/// paused, on a call, a session found after a crash, the next exercise coming up.
struct TrainSessionStateView<Actions: View>: View {
    let systemImage: String
    var tint: Color?
    var label: String?
    let title: String
    var figure: String?
    var message: String?
    private let actions: Actions

    @Environment(\.tideMood)
    private var mood

    init(
        systemImage: String,
        tint: Color? = nil,
        label: String? = nil,
        title: String,
        figure: String? = nil,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.label = label
        self.title = title
        self.figure = figure
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                TideIconTile(systemName: systemImage, tint: tint ?? mood.accent, size: TideTrainSession.stateTile)
                VStack(spacing: Tide.s2) {
                    if let label {
                        Text(label).tideLabel(tint ?? mood.accent)
                    }
                    Text(title)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let figure {
                        TideNumber(figure, size: TideTrainSession.stateFigure, relativeTo: .largeTitle)
                    }
                    if let message {
                        Text(message)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(spacing: Tide.s3) {
                    actions
                }
                .padding(.top, Tide.s2)
            }
            .frame(maxWidth: Tide.stateWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s8)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - TrainSessionChoiceRow

/// A label over a row of pick-one cells (breathing, form, RPE). Nothing is
/// chosen until the user taps; the cell that is chosen turns accent.
struct TrainSessionChoiceRow<Option: Hashable>: View {
    let title: String
    let options: [Option]
    let selection: Option?
    var height: CGFloat = TideTrainSession.choiceHeight
    let label: (Option) -> String
    let onSelect: (Option) -> Void

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text(title).tideLabel()
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Tide.s2))
                : AnyLayout(HStackLayout(spacing: Tide.s2))
            layout {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(option)
                        HapticManager.selection()
                    } label: {
                        Text(label(option))
                            .font(TideTrain.figure(.headline))
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                            .frame(maxWidth: .infinity, minHeight: height)
                    }
                    .buttonStyle(.trainChoice(isSelected: selection == option))
                }
            }
        }
    }
}

// MARK: - TrainSessionSection

/// A labelled glass card for a group of rows in a sheet or a summary:
/// small tracked heading, then the content, with hairlines between rows
/// added by the caller through `TrainSessionRule`.
struct TrainSessionSection<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: title, trailing: trailing)
            VStack(alignment: .leading, spacing: Tide.s3) {
                content
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }
}

// MARK: - TrainSessionRule

/// A hairline between two rows on a card.
struct TrainSessionRule: View {
    var body: some View {
        Rectangle()
            .fill(Tide.hairline)
            .frame(height: TideTrainSession.rule)
            .accessibilityHidden(true)
    }
}

// MARK: - TrainSessionDots

/// A trail of steps (warm-up moves, guided-run blocks): done ones are lit, the
/// current one is long and in the accent, the rest are dim.
struct TrainSessionDots: View {
    let count: Int
    let current: Int

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(spacing: Tide.s1) {
            ForEach(0 ..< max(count, 0), id: \.self) { index in
                Capsule()
                    .fill(fill(index))
                    .frame(width: index == current ? Tide.s6 : TideTrainSession.dot, height: TideTrainSession.dot)
            }
        }
        .animation(Tide.snap, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }

    private func fill(_ index: Int) -> Color {
        if index < current {
            return TideTrain.positive
        }
        return index == current ? mood.accent : Tide.fill
    }
}

// MARK: - TrainSessionHero

/// The one big thing on a live screen: a clock, a count or a distance. With a
/// `progress` it sits in a lit ring that fills as the step goes; without one it
/// sits on a glass card. Anything that belongs under it (a cap, a target, the
/// pace) goes in `below`.
struct TrainSessionHero<Below: View>: View {
    var label: String?
    var labelTint: Color = Tide.text2
    let value: String
    var progress: Double?
    var tint: Color?
    var valueColor: Color = Tide.text
    private let below: Below

    @ScaledMetric(relativeTo: .largeTitle)
    private var ringSize: CGFloat = TideTrainSession.restClock
    @ScaledMetric(relativeTo: .largeTitle)
    private var plainSize: CGFloat = TideTrainSession.bigClock

    init(
        label: String? = nil,
        labelTint: Color = Tide.text2,
        value: String,
        progress: Double? = nil,
        tint: Color? = nil,
        valueColor: Color = Tide.text,
        @ViewBuilder below: () -> Below
    ) {
        self.label = label
        self.labelTint = labelTint
        self.value = value
        self.progress = progress
        self.tint = tint
        self.valueColor = valueColor
        self.below = below()
    }

    var body: some View {
        VStack(spacing: Tide.s4) {
            if let label {
                Text(label).tideLabel(labelTint)
            }
            if let progress {
                TrainRing(progress: progress, tint: tint, diameter: TideTrainSession.restRing) {
                    Text(value)
                        .font(Tide.numeral(min(ringSize, TideTrainSession.restClockCap)))
                        .foregroundStyle(valueColor)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            } else {
                Text(value)
                    .font(Tide.numeral(plainSize))
                    .foregroundStyle(valueColor)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .tideCard(padding: Tide.s5)
            }
            below
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Train home kit (second wave)

// The hero of the day, the prompt cards and the scannable exercise list on
// Train home. Everything here is `Train*` so it cannot collide with another
// area's additions.

extension TideTrain {
    /// The square tile at the head of a prompt card (a date, a time, a symbol).
    static let askTile: CGFloat = 56
    /// The sets ring on the day hero.
    static let heroRing: CGFloat = 112
    /// One tick of the per-exercise set trail.
    static let tickWidth: CGFloat = 16
    static let tickHeight: CGFloat = 4
    /// The exercise picture in a list row; the number badge sits on its corner.
    static let rowPicture: CGFloat = 48
    /// The rail that joins the rows of a superset.
    static let groupRail: CGFloat = 3
    /// The most set ticks one row draws before it stops counting.
    static let tickLimit = 12
}

// MARK: - TrainFigureTile

/// A small tinted tile with a tracked label over a big figure: a weekday over
/// its date, a month over a week range, a venue over a clock time.
struct TrainFigureTile: View {
    let label: String
    let figure: String
    var tint: Color = Tide.text2

    @ScaledMetric(relativeTo: .title)
    private var side: CGFloat = TideTrain.askTile
    @ScaledMetric(relativeTo: .title3)
    private var figureSize: CGFloat = Tide.numeralS

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(Tide.label)
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
            Text(figure)
                .font(Tide.numeral(figureSize))
                .foregroundStyle(Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .padding(.horizontal, Tide.s2)
        .frame(minWidth: side, minHeight: side)
        .background(tint.opacity(0.16), in: .rect(cornerRadius: Tide.controlRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    init(label: String, figure: String, tint: Color = Tide.text2) {
        self.label = label
        self.figure = figure
        self.tint = tint
    }

    /// A day: its weekday over its date.
    init(date: Date, tint: Color = Tide.text2) {
        self.init(
            label: date.formatted(.dateTime.weekday(.abbreviated)),
            figure: date.formatted(.dateTime.day()),
            tint: tint
        )
    }
}

// MARK: - TrainAskCard

/// A question Train puts to you: one tinted tile that says what it is about
/// (a date, a week, a clock time or a symbol), a label, the ask in one line,
/// a line of why, then one filled action and quieter ones under it. Every
/// prompt on Train home is one of these, so each reads as its own object.
struct TrainAskCard<Tile: View, Actions: View>: View {
    let label: String
    var tint: Color = .accentColor
    let title: String
    var message: String?
    private let tile: Tile
    private let actions: Actions
    private let hasActions: Bool

    @Environment(\.dynamicTypeSize)
    private var typeSize

    init(
        label: String,
        tint: Color = Color.accentColor,
        title: String,
        message: String? = nil,
        @ViewBuilder tile: () -> Tile,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = label
        self.tint = tint
        self.title = title
        self.message = message
        self.tile = tile()
        self.actions = actions()
        hasActions = true
    }

    var body: some View {
        let head = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s3))
        VStack(alignment: .leading, spacing: Tide.s3) {
            head {
                tile
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(label).tideLabel(tint)
                    Text(title)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if hasActions {
                VStack(spacing: Tide.s1) {
                    actions
                }
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .trainSessionOutline(tint)
    }
}

extension TrainAskCard where Actions == EmptyView {
    /// A card that only informs: no actions under it.
    init(
        label: String,
        tint: Color = Color.accentColor,
        title: String,
        message: String? = nil,
        @ViewBuilder tile: () -> Tile
    ) {
        self.label = label
        self.tint = tint
        self.title = title
        self.message = message
        self.tile = tile()
        actions = EmptyView()
        hasActions = false
    }
}

// MARK: - TrainQuietButtonStyle

/// A text-only action under a filled one ("Not a match", "Upload only"): full
/// width so it is easy to hit, but with no surface.
struct TrainQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Tide.hit)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TrainQuietButtonStyle {
    static var trainQuiet: TrainQuietButtonStyle {
        TrainQuietButtonStyle()
    }
}

// MARK: - TrainDayHero

/// The hero of a Train day: what today is as one number (minutes), the plan as
/// a sentence (exercises, sets), a lit ring or a symbol on the right, and one
/// footer line (how recovery shaped it).
struct TrainDayHero<Trailing: View, Footer: View>: View {
    struct Stat: Identifiable {
        let value: String
        let label: String
        var id: String {
            label
        }
    }

    let label: String
    let figure: String
    var unit: String?
    var caption: String?
    var stats: [Stat] = []
    var chips: [String] = []
    private let trailing: Trailing
    private let footer: Footer

    @Environment(\.dynamicTypeSize)
    private var typeSize

    init(
        label: String,
        figure: String,
        unit: String? = nil,
        caption: String? = nil,
        stats: [Stat] = [],
        chips: [String] = [],
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder footer: () -> Footer
    ) {
        self.label = label
        self.figure = figure
        self.unit = unit
        self.caption = caption
        self.stats = stats
        self.chips = chips
        self.trailing = trailing()
        self.footer = footer()
    }

    var body: some View {
        let split = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s3))
        VStack(alignment: .leading, spacing: Tide.s4) {
            split {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text(label).tideLabel()
                    TideNumber(figure, unit: unit, size: Tide.numeralL, relativeTo: .largeTitle)
                    if let caption {
                        Text(caption)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !stats.isEmpty {
                        statLine
                    }
                    if !chips.isEmpty {
                        FlowLayout(spacing: Tide.s1, lineSpacing: Tide.s1) {
                            ForEach(chips, id: \.self) { chip in
                                TrainTag(text: chip)
                            }
                        }
                    }
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)
                }
                trailing
            }
            TrainSessionRule()
            footer
        }
        .tideCard(padding: Tide.s5)
    }

    /// "6 exercises   18 sets": the figure first, the word after, like a sentence.
    private var statLine: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Tide.s4))
        return layout {
            ForEach(stats) { stat in
                HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                    TideNumber(stat.value, size: Tide.numeralS, relativeTo: .title3)
                    Text(stat.label)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - TrainSetsRing

/// The sets of the day as a lit ring: done over total in the middle.
struct TrainSetsRing: View {
    let done: Int
    let total: Int
    var tint: Color?

    private var fraction: Double {
        total > 0 ? Double(done) / Double(total) : 0
    }

    var body: some View {
        TrainRing(progress: fraction, tint: tint, diameter: TideTrain.heroRing) {
            VStack(spacing: Tide.hair) {
                TideNumber("\(done)/\(total)", size: Tide.numeralS, relativeTo: .title2)
                Text("Sets").tideLabel()
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sets")
        .accessibilityValue("\(done) of \(total) done")
    }
}

// MARK: - TrainSetTicks

/// One small capsule per working set: done sets are lit. The trail of an
/// exercise row once a session has started.
struct TrainSetTicks: View {
    let done: Int
    let total: Int
    /// What the ticks count, for VoiceOver ("Sets", "Questions").
    var label = "Sets"

    var body: some View {
        HStack(spacing: Tide.s1) {
            ForEach(0 ..< min(max(total, 0), TideTrain.tickLimit), id: \.self) { index in
                Capsule()
                    .fill(index < done ? TideTrain.positive : Tide.fillStrong)
                    .frame(width: TideTrain.tickWidth, height: TideTrain.tickHeight)
            }
        }
        .animation(Tide.snap, value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(done) of \(total) done")
    }
}

// MARK: - TrainRowPressStyle

/// A row inside a card that lights up while it is pressed.
struct TrainRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Tide.fill : Color.clear)
            .animation(Tide.snap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TrainRowPressStyle {
    static var trainRow: TrainRowPressStyle {
        TrainRowPressStyle()
    }
}

// MARK: - TrainListCard

/// One glass card for a list of rows; the rows draw their own padding and the
/// caller puts `TrainPlanDivider`s between them.
struct TrainListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .tideCard(padding: 0, radius: Tide.tileRadius)
        .clipShape(.rect(cornerRadius: Tide.tileRadius, style: .continuous))
    }
}
