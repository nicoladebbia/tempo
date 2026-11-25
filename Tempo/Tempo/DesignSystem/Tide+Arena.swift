//
// Tide+Arena.swift
// Tempo
//
// Reusable Tide pieces first built for Arena, Recovery and Lockdown: a pill
// picker, avatars, empty states, tiles, a scroll page and the colours that
// carry meaning in those areas (leagues, rarities, XP sources).
//
// Everything here sits on the tokens in TideTokens.swift and the components in
// TideComponents.swift; nothing in those files is changed.
//

import SwiftUI

// MARK: - TideTone

/// Data colours for Arena, Recovery and Lockdown. All of them are light enough
/// to carry text or a thin line over the ink background.
enum TideTone {
    static let mint = Color(red: 0.42, green: 0.94, blue: 0.66)
    static let amber = Color(red: 1.00, green: 0.80, blue: 0.40)
    static let violet = Color(red: 0.72, green: 0.62, blue: 1.00)
    static let sky = Color(red: 0.55, green: 0.76, blue: 1.00)
    static let indigo = Color(red: 0.50, green: 0.58, blue: 1.00)
    static let gold = Color(red: 1.00, green: 0.84, blue: 0.30)
}

extension League {
    /// League colour on the Tide palette.
    var tideTint: Color {
        switch self {
        case .bronze: Color(red: 0.93, green: 0.63, blue: 0.40)
        case .silver: Color(red: 0.80, green: 0.83, blue: 0.90)
        case .gold: TideTone.gold
        case .diamond: Tide.water
        case .champion: Tide.danger
        }
    }
}

extension AchievementRarity {
    var tideTint: Color {
        switch self {
        case .common: Tide.text2
        case .uncommon: TideTone.mint
        case .rare: Tide.water
        case .epic: TideTone.violet
        case .legendary: TideTone.amber
        }
    }

    var tideSymbol: String {
        switch self {
        case .common,
             .uncommon: "star.fill"
        case .rare: "star.circle.fill"
        case .epic: "shield.checkered"
        case .legendary: "crown.fill"
        }
    }

    var tideName: String {
        rawValue.capitalized
    }
}

extension XPSource {
    var tideSymbol: String {
        switch self {
        case .workout: "dumbbell.fill"
        case .study: "book.fill"
        case .meal: "fork.knife"
        case .sleep: "moon.fill"
        case .steps: "figure.walk"
        case .nonNegotiable: "checklist"
        case .streak: "flame.fill"
        case .challenge: "flag.2.crossed.fill"
        case .achievement: "medal.fill"
        case .perfectDay: "star.fill"
        case .penalty: "exclamationmark.triangle.fill"
        case .earlyBird: "sunrise.fill"
        }
    }
}

// MARK: - Layout tokens

extension Tide {
    /// A hairline between rows.
    static let rule: CGFloat = 1
    /// A figure bigger than the hero figure on Today: a level, a timer.
    static let numeralHero: CGFloat = 72
    /// Avatars: list rows and the podium.
    static let avatar: CGFloat = 40
    static let avatarLarge: CGFloat = 56
    /// The score dial on a detail page.
    static let dialDetail: CGFloat = 200
    /// The timer dial on the focus screen.
    static let dialTimer: CGFloat = 300
    /// The dial's once-a-second tick: linear, so the ring never stutters.
    static let tick = Animation.linear(duration: 1)
}

// MARK: - TideScrollPage

/// The standard page: a scrolling column of glass cards over the Tide field.
/// `energy` is how lively the field is (1 on a tab home, the default below it).
struct TideScrollPage<Content: View>: View {
    var energy: Double = Tide.sheetEnergy
    var spacing: CGFloat = Tide.s4
    var spacer: CGFloat = Tide.s2
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: spacing) {
                content
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, spacer)
            .padding(.bottom, Tide.s8)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .tidePage(energy: energy)
    }
}

// MARK: - TidePillPicker

/// A glass segmented control: the chosen pill takes the mood colour and slides
/// to the next choice.
struct TidePillPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var label = "Choose"
    var stacksThree = false

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Namespace
    private var pill

    /// At accessibility text sizes four short words no longer share one row: they wrap to
    /// two rows instead of shrinking. Three longer words can ask to stack in one column.
    private var wraps: Bool {
        typeSize.isAccessibilitySize && (options.count > 3 || (stacksThree && options.count == 3))
    }

    var body: some View {
        let layout = wraps
            ? AnyLayout(WrappingPillRows(columns: options.count == 3 ? 1 : 2, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s1))
        layout {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(Tide.snap) { selection = option }
                } label: {
                    Text(title(option))
                        .font(Tide.bodyStrong)
                        .foregroundStyle(selected ? Tide.ink : Tide.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit - Tide.s2)
                        .background {
                            if selected {
                                Capsule().fill(mood.accent).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Tide.s1)
        .glassEffect(.regular.tint(Tide.glassControl), in: .rect(cornerRadius: wraps ? Tide.controlRadius + Tide.s2 : Tide.hit))
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - WrappingPillRows

/// A grid of equal cells filled row by row. Used by the picker when it wraps.
private struct WrappingPillRows: Layout {
    var columns: Int
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let cell = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let rows = (subviews.count + columns - 1) / columns
        let heights = (0 ..< rows).map { row in
            subviews[row * columns ..< min((row + 1) * columns, subviews.count)]
                .map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }
                .max() ?? 0
        }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(rows - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var y = bounds.minY
        var index = 0
        while index < subviews.count {
            let end = min(index + columns, subviews.count)
            let rowHeight = subviews[index ..< end]
                .map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }
                .max() ?? 0
            for (offset, subview) in subviews[index ..< end].enumerated() {
                subview.place(
                    at: CGPoint(x: bounds.minX + CGFloat(offset) * (cell + spacing), y: y),
                    proposal: ProposedViewSize(width: cell, height: rowHeight)
                )
            }
            y += rowHeight + spacing
            index = end
        }
    }
}

// MARK: - TideFilterChip

/// A chip that can be on: the chosen one takes the mood colour.
struct TideFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(Tide.bodyStrong)
                .foregroundStyle(isSelected ? Tide.ink : Tide.text)
                .lineLimit(1)
                .padding(.horizontal, Tide.s4)
                .frame(minHeight: Tide.hit)
                .background {
                    if isSelected {
                        Capsule().fill(mood.accent)
                    }
                }
                .glassEffect(isSelected ? .identity : .regular.interactive(), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(Tide.snap, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - TideInitialAvatar

/// A person's initial in a tinted disc.
struct TideInitialAvatar: View {
    let name: String
    var size: CGFloat = Tide.avatar
    var tint: Color?

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .headline)
    private var scale: CGFloat = 1

    var body: some View {
        let color = tint ?? mood.accent
        Text(String(name.prefix(1)).uppercased())
            .font(Tide.numeral(size * 0.42 * scale, .semibold))
            .foregroundStyle(color)
            .frame(width: size * scale, height: size * scale)
            .background(color.opacity(0.18), in: .circle)
            .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: Tide.rule))
            .accessibilityHidden(true)
    }
}

// MARK: - TideAreaIconTile

/// A symbol in a softly tinted rounded square.
struct TideAreaIconTile: View {
    let systemName: String
    var tint: Color = Tide.text
    var size: CGFloat = Tide.avatar

    @ScaledMetric(relativeTo: .headline)
    private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: systemName)
            .font(Tide.headline)
            .foregroundStyle(tint)
            .frame(width: size * scale, height: size * scale)
            .background(tint.opacity(0.16), in: .rect(cornerRadius: Tide.controlRadius))
            .accessibilityHidden(true)
    }
}

// MARK: - TideStatusPill

/// A small tinted label: a status, a league, a duration.
struct TideStatusPill: View {
    let text: String
    var tint: Color = Tide.text2
    var systemImage: String?

    var body: some View {
        HStack(spacing: Tide.s1) {
            if let systemImage {
                Image(systemName: systemImage).font(Tide.label)
            }
            Text(text).tideLabel(tint).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Tide.s3)
        .padding(.vertical, Tide.s1 + Tide.hair)
        .background(tint.opacity(0.16), in: .capsule)
    }
}

// MARK: - TideDivider

/// A hairline that separates rows inside a card.
struct TideDivider: View {
    var body: some View {
        Rectangle()
            .fill(Tide.hairline)
            .frame(height: Tide.rule)
            .accessibilityHidden(true)
    }
}

// MARK: - TideEmptyPanel

/// Nothing here yet: an icon, one line, a sentence and (optionally) the next step.
struct TideEmptyPanel: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: () -> Void = {}

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
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.tideGlass)
                    .padding(.top, Tide.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tide.s6)
        .padding(.horizontal, Tide.s4)
        .accessibilityElement(children: actionTitle == nil ? .combine : .contain)
    }
}

// MARK: - TideMetricTile

/// A glass tile: a small label above one figure.
struct TideMetricTile: View {
    let label: String
    let value: String
    var unit: String?
    var detail: String?
    var tint: Color = Tide.text
    var systemImage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(spacing: Tide.s1 + Tide.hair) {
                if let systemImage {
                    Image(systemName: systemImage).font(Tide.label).foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
                Text(label).tideLabel().lineLimit(1).minimumScaleFactor(Tide.labelShrink)
            }
            TideNumber(value, unit: unit, size: Tide.numeralS + Tide.s1, relativeTo: .title3, color: tint)
            if let detail {
                Text(detail).font(Tide.caption).foregroundStyle(Tide.text2).lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Text field

extension View {
    /// A field with a leading symbol on a soft fill (search, names, numbers).
    func tideField(systemImage: String? = nil) -> some View {
        HStack(spacing: Tide.s3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            self
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .tint(Tide.text)
        }
        .padding(.horizontal, Tide.s4)
        .frame(minHeight: Tide.hit + Tide.s1)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: Tide.controlRadius).strokeBorder(Tide.hairline, lineWidth: Tide.rule))
    }

    /// A row of a native `List` (kept for swipe-to-delete, drag-to-reorder and
    /// forms): a soft ink panel with a hairline between rows.
    func tideListRow() -> some View {
        listRowBackground(Tide.glassCard)
            .listRowSeparatorTint(Tide.hairline)
    }

    /// Zoom-transition source, only when a namespace was passed in.
    @ViewBuilder
    func tideZoomSource(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - TideCloseButton

/// The round glass close button for a sheet's toolbar.
struct TideCloseButton: View {
    var label = "Close"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .frame(width: Tide.hit, height: Tide.hit)
                .contentShape(.circle)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - TideInfoButton

/// A small "i" that opens an explainer sheet. For a number that sits inside
/// something that already does something when tapped (a tile that opens a chart,
/// a row that navigates), where wrapping the number itself would nest buttons.
struct TideInfoButton: View {
    let explainer: Explainer

    var body: some View {
        Image(systemName: "info.circle")
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text2)
            .frame(width: Tide.hit, height: Tide.hit)
            .contentShape(.circle)
            .explains(explainer)
            .accessibilityLabel(Text(explainer.title))
    }
}

// MARK: - TideTimerDial

/// The focus timer's dial: the same shader-lit ring and 60-tick scale as the
/// score dial, but filled by `progress` (0...1) once a second, with any view
/// in the middle (the condensed numerals).
struct TideTimerDial<Center: View>: View {
    let progress: Double
    var accent: Color?
    var diameter: CGFloat = Tide.dialTimer
    @ViewBuilder var center: Center

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var shown: Double = 0

    private var target: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            TideClock { time in
                TideTimerDialFace(progress: shown, time: time, accent: accent ?? mood.accent)
            }
            center
                .padding(.horizontal, diameter * 0.16)
                // A small dial is a fixed instrument: what sits inside it stops
                // growing before it touches the ring. The big timer keeps scaling.
                .dynamicTypeSize(...(diameter <= Tide.dialHero ? DynamicTypeSize.xxxLarge : DynamicTypeSize.accessibility5))
        }
        .frame(width: diameter, height: diameter)
        .onAppear { shown = target }
        .onChange(of: target) { _, new in
            withAnimation(reduceMotion ? nil : Tide.tick) { shown = new }
        }
    }
}

// MARK: - TideTimerDialFace

private struct TideTimerDialFace: View, Animatable {
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
            .accessibilityHidden(true)
    }
}

// MARK: - TideOrdersCard

/// The drill sergeant's line: a tinted symbol, a tracked label and the order itself.
struct TideOrdersCard: View {
    let message: String
    var intensity: DrillSergeantIntensity = .standard

    @Environment(\.tideMood)
    private var mood

    private var tint: Color {
        switch intensity {
        case .encouraging: TideTone.mint
        case .standard: mood.accent
        case .urgent: TideTone.amber
        case .critical: Tide.danger
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            TideAreaIconTile(systemName: intensity.icon, tint: tint)
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(intensity.label).tideLabel(tint)
                Text(message)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ArenaListSkeleton

/// What a ranked list shows while it loads: a podium-shaped block and a few
/// rows, breathing. It keeps the page's shape, so nothing jumps when the data
/// lands. Reduce Motion holds it still.
struct ArenaListSkeleton: View {
    var rows = 3
    /// What VoiceOver says while the list loads.
    var label = "Loading"

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var dim = false

    var body: some View {
        VStack(spacing: Tide.s4) {
            HStack(alignment: .bottom, spacing: Tide.s3) {
                ForEach([2, 3, 1], id: \.self) { rank in
                    RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                        .fill(Tide.track)
                        .frame(height: Tide.s10 * (rank == 3 ? 2 : (rank == 2 ? 3 : 4)))
                }
            }
            VStack(spacing: Tide.s3) {
                ForEach(0 ..< rows, id: \.self) { _ in
                    HStack(spacing: Tide.s3) {
                        Circle().fill(Tide.track).frame(width: Tide.avatar, height: Tide.avatar)
                        VStack(alignment: .leading, spacing: Tide.s2) {
                            Capsule().fill(Tide.track).frame(width: Tide.s10 * 2.5, height: Tide.s3)
                            Capsule().fill(Tide.track).frame(width: Tide.s10 * 1.5, height: Tide.s2 + Tide.s1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .tideCard(padding: Tide.s4)
        }
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            if !reduceMotion {
                withAnimation(Tide.recoveryPulse) { dim = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

// MARK: - ArenaLinkRow

/// One line that opens a page: a tinted symbol, a title, what is inside, a
/// chevron. Several rows in one card read as a list, not as a stack of cards.
struct ArenaLinkRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var tint: Color = Tide.text2

    var body: some View {
        HStack(spacing: Tide.s3) {
            TideAreaIconTile(systemName: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Text(detail)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Tide.hit)
        .padding(.vertical, Tide.s1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ArenaReveal

/// A section settles into place once, in order down the page. Reduce Motion
/// shows it finished.
private struct ArenaReveal: ViewModifier {
    let index: Int

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var shown = false

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : Tide.s4)
            .onAppear {
                guard !shown else {
                    return
                }
                withAnimation(Tide.settle.delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

extension View {
    /// Fades and lifts this section in, `index` places down the page.
    func arenaReveal(_ index: Int) -> some View {
        modifier(ArenaReveal(index: index))
    }
}

// MARK: - ArenaGhostAvatars

/// Three empty places on a leaderboard: dashed discs, a plus on the first.
struct ArenaGhostAvatars: View {
    @ScaledMetric(relativeTo: .headline)
    private var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: -Tide.s2) {
            ForEach(0 ..< 3, id: \.self) { index in
                ZStack {
                    Circle().fill(Tide.fill)
                    Circle().strokeBorder(Tide.text3, style: StrokeStyle(lineWidth: Tide.rule, dash: [Tide.s1, Tide.s1]))
                    if index == 0 {
                        Image(systemName: "plus")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text2)
                    }
                }
                .frame(width: Tide.avatar * scale, height: Tide.avatar * scale)
                .zIndex(Double(3 - index))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - ArenaBurst

/// The burst of rings and sparks (the `tideBurst` shader) that opens a moment:
/// an unlock, a finished run, an earned badge. It plays once, then holds its
/// last, nearly empty frame and stops redrawing. Reduce Motion shows that
/// frame at once.
struct ArenaBurst: View {
    var accent: Color
    /// Seconds the burst plays.
    var seconds = 4.5

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var start = Date()
    @State
    private var done = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || done)) { context in
            let t = reduceMotion || done ? seconds : min(context.date.timeIntervalSince(start), seconds)
            Rectangle()
                .fill(Tide.text)
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.tideBurst(
                        .float2(proxy.size), .float(t), .color(accent), .color(Tide.carbs)
                    ))
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { start = Date() }
        .task {
            try? await Task.sleep(for: .seconds(seconds))
            done = true
        }
    }
}

// MARK: - ArenaEmptyArt

/// The picture on an empty page: a symbol on a round glass disc.
struct ArenaEmptyArt: View {
    let systemImage: String
    var tint: Color?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        let color = tint ?? mood.accent
        Image(systemName: systemImage)
            .font(Tide.numeral(Tide.numeralM))
            .foregroundStyle(color)
            .frame(width: Tide.dialSheet, height: Tide.dialSheet)
            .glassEffect(.regular.tint(color.opacity(0.14)), in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - ArenaEmptyPage

/// A whole page with nothing on it yet: one picture, one line and one next
/// step, centred, with the step under the thumb. It scrolls only when the
/// text is too big to fit.
struct ArenaEmptyPage<Art: View>: View {
    let title: String
    let message: String
    var actionTitle: String?
    var actionSystemImage = "plus"
    var action: () -> Void = {}
    /// A quieter second way on, under the main step.
    var secondaryTitle: String?
    var secondaryAction: () -> Void = {}
    @ViewBuilder var art: Art

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Tide.s5) {
                    Spacer(minLength: Tide.s6)
                    art
                    VStack(spacing: Tide.s2) {
                        Text(title)
                            .font(Tide.title2)
                            .foregroundStyle(Tide.text)
                            .multilineTextAlignment(.center)
                        Text(message)
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Tide.s6)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .padding(.horizontal, Tide.edge)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let actionTitle {
                VStack(spacing: Tide.s2) {
                    Button(action: action) {
                        Label(actionTitle, systemImage: actionSystemImage)
                    }
                    .buttonStyle(.tidePrimary)

                    if let secondaryTitle {
                        Button(secondaryTitle, action: secondaryAction)
                            .buttonStyle(.tideGlass)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s2)
            }
        }
        .tidePage()
    }
}

// MARK: - ArenaEarnChip

/// A way to earn XP: a symbol and a short word in a soft tile.
struct ArenaEarnChip: View {
    let systemImage: String
    let title: String
    var tint: Color = Tide.text
    /// Symbol beside the word instead of above it (the large text sizes).
    var sideBySide = false

    var body: some View {
        let layout = sideBySide
            ? AnyLayout(HStackLayout(spacing: Tide.s3))
            : AnyLayout(VStackLayout(spacing: Tide.s2))
        layout {
            Image(systemName: systemImage)
                .font(Tide.headline)
                .foregroundStyle(tint)
            Text(title)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .frame(maxWidth: .infinity, alignment: sideBySide ? .leading : .center)
        .padding(.vertical, Tide.s3)
        .padding(.horizontal, Tide.s3)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: Tide.controlRadius))
        .accessibilityElement(children: .combine)
    }
}
