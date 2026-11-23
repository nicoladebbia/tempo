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

// MARK: - TideCardPressStyle

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

    @Environment(\.tideMood)
    private var mood
    @Namespace
    private var pill

    var body: some View {
        HStack(spacing: Tide.s1) {
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
        .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
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

// MARK: - TideIconTile

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
