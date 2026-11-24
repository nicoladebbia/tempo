//
// Tide+Onboarding.swift
// Tempo
//
// The pieces every onboarding step is built from: a scaffold with a big title,
// scrolling content and one primary capsule pinned to the bottom; selectable
// rows and chips; a large symbol tile for the permission steps.
//

import SwiftUI

// MARK: - OnboardingScaffold

/// One onboarding step: a large title (and an optional line under it), the
/// content scrolling beneath, and the primary action pinned at the bottom with
/// an optional quiet skip under it. The page field is drawn by the container.
struct OnboardingScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var primaryTitle: String?
    var primaryEnabled = true
    var primaryAction: (() -> Void)?
    var skipTitle = "SKIP"
    var skipAction: (() -> Void)?
    var skipEnabled = true
    /// A failure to show right above the buttons, where it is never below the fold.
    var errorMessage: String?
    /// Centre the title and content on the page (a hero step) instead of
    /// starting at the top.
    var centered = false
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var appeared = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: centered ? .center : .leading, spacing: Tide.s6) {
                header
                    .modifier(OnboardingEntrance(index: 0, appeared: appeared))
                // Each block of the step settles in a beat after the one above.
                Group(subviews: content) { blocks in
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        block.modifier(OnboardingEntrance(index: index + 1, appeared: appeared))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .padding(.horizontal, Tide.edge)
            .padding(.top, centered ? Tide.s6 : Tide.s4)
            .padding(.bottom, Tide.s6)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : Tide.lively.delay(Tide.onboardingStagger * 3), value: appeared)
        }
        .onAppear { appeared = true }
    }

    private var header: some View {
        VStack(alignment: centered ? .center : .leading, spacing: Tide.s2) {
            Text(title)
                .font(centered ? Tide.largeTitle : Tide.title)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if primaryAction != nil || skipAction != nil {
            VStack(spacing: Tide.s1) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Tide.s1)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if let primaryTitle, let primaryAction {
                    Button(primaryTitle, action: primaryAction)
                        .buttonStyle(.tidePrimary)
                        .disabled(!primaryEnabled)
                }
                if let skipAction {
                    Button(action: skipAction) {
                        Text(skipTitle)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text2)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!skipEnabled)
                }
            }
            .modifier(OnboardingFooterBar())
        }
    }
}

// MARK: - OnboardingFooterBar

/// The bar under a scrolling step: padded to the page edge, its text capped at
/// the first accessibility size, and a fade so scrolling content dips out under
/// the buttons instead of running into them. Used by the scaffold and by any
/// step that pins its own bottom controls (the sign-in step).
struct OnboardingFooterBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Tide.edge)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.top, Tide.s6)
            .padding(.bottom, Tide.s2)
            .background {
                LinearGradient(
                    stops: [
                        .init(color: Tide.ink.opacity(0), location: 0),
                        .init(color: Tide.ink.opacity(0.94), location: 0.42),
                        .init(color: Tide.ink.opacity(0.97), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
    }
}

// MARK: - OnboardingEntrance

extension Tide {
    /// Delay between one block of an onboarding step and the next settling in.
    static let onboardingStagger: Double = 0.06
}

// MARK: - OnboardingEntrance

/// Fades a block in and lifts it a few points, a beat after the one above.
/// Reduce Motion shows it at once.
private struct OnboardingEntrance: ViewModifier {
    let index: Int
    let appeared: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : Tide.s3)
            .animation(
                reduceMotion ? nil : Tide.lively.delay(Double(min(index, 5)) * Tide.onboardingStagger),
                value: appeared
            )
    }
}

// MARK: - OnboardingOptionRow

/// A selectable row: glass, with the accent ring and a check when chosen.
struct OnboardingOptionRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    /// 1...3 draws signal bars in front of the title (an experience level).
    var level: Int?
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tide.s3) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Tide.headline)
                        .foregroundStyle(isSelected ? mood.accent : Tide.text2)
                        .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(width: Tide.icon)
                        .accessibilityHidden(true)
                } else if let level {
                    OnboardingLevelBars(level: level, isLit: isSelected)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(width: Tide.icon)
                }
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(title)
                        .font(Tide.headline)
                        .foregroundStyle(isSelected ? Tide.text : Tide.text.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Tide.s2)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Tide.headline)
                    .foregroundStyle(isSelected ? mood.accent : Tide.text3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Tide.s4)
            .padding(.vertical, Tide.s3)
            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s3, alignment: .leading)
            .glassEffect(
                .regular.tint(isSelected ? mood.accent.opacity(0.22) : Tide.glassControl),
                in: .rect(cornerRadius: Tide.tileRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                    .strokeBorder(isSelected ? mood.accent : Color.clear, lineWidth: Tide.focusLine)
            }
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .animation(Tide.snap, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - OnboardingChip

/// A selectable pill ("Social Media"): accent fill with ink text when on.
struct OnboardingChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    /// Share the row evenly with its siblings (a day number, YES / NO) instead
    /// of hugging the title.
    var expands = false
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tide.s2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Tide.caption)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Tide.bodyStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .foregroundStyle(isSelected ? Tide.ink : Tide.text)
            .frame(maxWidth: expands ? .infinity : nil)
            .padding(.horizontal, expands ? Tide.s1 : Tide.s4)
            .frame(minHeight: Tide.hit)
            .background(isSelected ? mood.accent : Tide.fill, in: .capsule)
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.clear : Tide.hairline, lineWidth: 1)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(Tide.snap, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - OnboardingSectionLabel

/// The small tracked label over a group of fields or options.
struct OnboardingSectionLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        TideSectionLabel(title: text, trailing: trailing)
    }
}

// MARK: - OnboardingNote

/// A quiet footnote under a control.
struct OnboardingNote: View {
    let text: String
    var systemImage: String?

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - OnboardingHeroTile

/// The large symbol on a permission or celebration step, breathing in its halo.
struct OnboardingHeroTile: View {
    let systemName: String
    var tint: Color?

    var body: some View {
        TideStateMark(systemName: systemName, tint: tint, tileSize: Tide.tileLarge + Tide.s2, reach: Tide.s10)
    }
}

// MARK: - OnboardingBenefitRow

/// An icon and one line, for the "what you get" lists.
struct OnboardingBenefitRow: View {
    let systemImage: String
    let text: String
    var tint: Color?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: systemImage)
                .font(Tide.headline)
                .foregroundStyle(tint ?? mood.accent)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: Tide.icon)
                .accessibilityHidden(true)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: Tide.icon + Tide.s2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - OnboardingFormat

/// How a time or a stretch of hours reads on every onboarding step.
enum OnboardingFormat {
    /// "7:00 AM", in the person's own clock style.
    static func clock(_ minutes: Int) -> String {
        let day = 24 * 60
        let wrapped = ((minutes % day) + day) % day
        let date = Calendar.current.date(from: DateComponents(hour: wrapped / 60, minute: wrapped % 60)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "8h" or "7h 30m".
    static func hours(_ hours: Double) -> String {
        let whole = Int(hours)
        let minutes = Int(((hours - Double(whole)) * 60).rounded())
        return minutes == 0 ? "\(whole)h" : "\(whole)h \(minutes)m"
    }
}

// MARK: - OnboardingLevelBars

/// Three rising bars, the first `level` lit: an experience level at a glance.
struct OnboardingLevelBars: View {
    let level: Int
    var isLit = false

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(alignment: .bottom, spacing: Tide.hair) {
            ForEach(1 ... 3, id: \.self) { index in
                Capsule()
                    .fill(index <= level ? (isLit ? mood.accent : Tide.text2) : Tide.track)
                    .frame(width: Tide.s1, height: Tide.s2 + CGFloat(index) * Tide.s1 + Tide.s1)
            }
        }
        .animation(Tide.snap, value: isLit)
        .accessibilityHidden(true)
    }
}

// MARK: - OnboardingChoiceCard

/// A rich selectable card: a symbol tile, a title and an optional line.
/// Picked, the tile fills with the accent, the card takes an accent ring and
/// the symbol bounces. `stacked` is for a grid of big choices (a goal),
/// `inline` for a row with a tile, `compact` for a dense grid (an identity).
struct OnboardingChoiceCard: View {
    enum Layout {
        case stacked
        case inline
        case compact
    }

    let title: String
    var subtitle: String?
    let systemImage: String
    let isSelected: Bool
    var layout: Layout = .stacked
    /// Several can be picked: the mark is a square tick, not a round one.
    var isMulti = false
    let action: () -> Void

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .headline)
    private var tileSize: CGFloat = Tide.tile + Tide.s1

    /// Inline cards become stacked at accessibility sizes: the label gets the
    /// full width instead of what is left between the tile and the mark.
    private var resolvedLayout: Layout {
        layout == .inline && typeSize.isAccessibilitySize ? .stacked : layout
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, layout == .compact ? Tide.s3 : Tide.s4)
                .padding(.vertical, layout == .compact ? Tide.s3 : Tide.s4)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: layout == .stacked ? .infinity : nil,
                    alignment: layout == .stacked ? .topLeading : .leading
                )
                .frame(minHeight: layout == .stacked ? Tide.tileLarge + Tide.s8 : Tide.hit + Tide.s3)
                .glassEffect(
                    .regular.tint(isSelected ? mood.accent.opacity(0.22) : Tide.glassControl),
                    in: .rect(cornerRadius: Tide.tileRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                        .strokeBorder(isSelected ? mood.accent : Color.clear, lineWidth: Tide.focusLine)
                }
                .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
        .animation(Tide.snap, value: isSelected)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch resolvedLayout {
        case .stacked:
            VStack(alignment: .leading, spacing: Tide.s3) {
                HStack(alignment: .top) {
                    tile
                    Spacer(minLength: Tide.s2)
                    mark
                }
                Spacer(minLength: 0)
                labels
            }
        case .inline:
            HStack(spacing: Tide.s3) {
                tile
                labels
                Spacer(minLength: Tide.s2)
                mark
            }
        case .compact:
            HStack(spacing: Tide.s2) {
                Image(systemName: systemImage)
                    .font(Tide.headline)
                    .foregroundStyle(isSelected ? mood.accent : Tide.text2)
                    .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(width: Tide.icon)
                    .accessibilityHidden(true)
                labels
                Spacer(minLength: 0)
            }
        }
    }

    private var tile: some View {
        Image(systemName: systemImage)
            .font(.system(size: tileSize * 0.46, weight: .semibold))
            .foregroundStyle(isSelected ? Tide.ink : mood.accent)
            .symbolEffect(.bounce, value: reduceMotion ? false : isSelected)
            .frame(width: tileSize, height: tileSize)
            .background(
                isSelected ? mood.accent : Tide.fill,
                in: .rect(cornerRadius: Tide.controlRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var mark: some View {
        Image(systemName: isSelected
            ? (isMulti ? "checkmark.square.fill" : "checkmark.circle.fill")
            : (isMulti ? "square" : "circle"))
            .font(Tide.headline)
            .foregroundStyle(isSelected ? mood.accent : Tide.text3)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text(title)
                .font(layout == .compact ? Tide.bodyStrong : Tide.headline)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.leading)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - OnboardingChoiceGrid

/// Choice cards in columns, one column at accessibility text sizes. A last
/// card left alone on its row stretches across it.
struct OnboardingChoiceGrid<Item: Hashable, Card: View>: View {
    let items: [Item]
    var columns = 2
    var stretchesLast = true
    @ViewBuilder let card: (Item) -> Card

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize || columns == 1 {
            VStack(spacing: Tide.s3) {
                ForEach(items, id: \.self) { card($0) }
            }
        } else {
            let rows = stride(from: 0, to: items.count, by: columns).map {
                Array(items[$0 ..< min($0 + columns, items.count)])
            }
            Grid(horizontalSpacing: Tide.s3, verticalSpacing: Tide.s3) {
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(rows[index], id: \.self) { item in
                            card(item)
                                .gridCellColumns(
                                    stretchesLast && rows[index].count < columns && item == rows[index].last
                                        ? columns - rows[index].count + 1 : 1
                                )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - OnboardingTimeControl

/// A time of day as a big figure with a round minus and plus: 15 minutes a
/// tap, repeating while held. Wraps past midnight. Replaces a small system
/// time field with something a thumb can hit.
struct OnboardingTimeControl: View {
    let title: String
    var systemImage: String?
    /// Minutes after midnight.
    @Binding
    var minutes: Int
    var step = 15

    @Environment(\.tideMood)
    private var mood
    @State
    private var nudges = 0

    var body: some View {
        HStack(spacing: Tide.s3) {
            if let systemImage {
                TideIconTile(systemName: systemImage, tint: mood.accent, size: Tide.tile + Tide.s1)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(title).tideLabel()
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                TideNumber(OnboardingFormat.clock(minutes), size: Tide.numeralM, relativeTo: .title)
                    .animation(Tide.snap, value: minutes)
            }
            Spacer(minLength: Tide.s2)
            GlassEffectContainer(spacing: Tide.s2) {
                HStack(spacing: Tide.s2) {
                    nudge(-step, symbol: "minus", label: "Earlier")
                    nudge(step, symbol: "plus", label: "Later")
                }
            }
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .sensoryFeedback(.selection, trigger: nudges)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(OnboardingFormat.clock(minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(step)
            case .decrement: move(-step)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Earlier") { move(-step) }
        .accessibilityAction(named: "Later") { move(step) }
    }

    private func nudge(_ delta: Int, symbol: String, label: String) -> some View {
        Button {
            move(delta)
        } label: {
            Image(systemName: symbol)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .frame(width: Tide.hit, height: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private func move(_ delta: Int) {
        let day = 24 * 60
        minutes = (((minutes + delta) % day) + day) % day
        nudges += 1
    }
}

// MARK: - OnboardingDayPillars

/// Pick a count from 1 to `count` by tapping a rising pillar: the pillars up
/// to the pick light up. A level meter for "days a week".
struct OnboardingDayPillars: View {
    @Binding
    var selection: Int
    var count = 7

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .title)
    private var base: CGFloat = Tide.s10 + Tide.s2
    @ScaledMetric(relativeTo: .title)
    private var rise: CGFloat = Tide.s2

    var body: some View {
        HStack(alignment: .bottom, spacing: Tide.s1) {
            ForEach(1 ... count, id: \.self) { day in
                pillar(day)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
    }

    private func pillar(_ day: Int) -> some View {
        let lit = day <= selection
        let current = day == selection
        return Button {
            withAnimation(Tide.snap) { selection = day }
        } label: {
            Text("\(day)")
                .font(Tide.numeral(Tide.numeralS))
                .foregroundStyle(lit ? Tide.ink : Tide.text2)
                .frame(maxWidth: .infinity)
                .frame(height: base + rise * CGFloat(day), alignment: .bottom)
                .padding(.bottom, Tide.s3)
                .background(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                        .fill(lit ? mood.accent.opacity(current ? 1 : 0.8) : Tide.fill)
                        .shadow(color: current ? mood.accent.opacity(0.5) : .clear, radius: Tide.s2)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day) \(day == 1 ? "day" : "days")")
        .accessibilityAddTraits(current ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - OnboardingSampleTag

/// "SAMPLE": the small tag on a preview that shows what a feature will look
/// like with made-up numbers.
struct OnboardingSampleTag: View {
    var title = "Sample"

    var body: some View {
        Text(title)
            .tideLabel(Tide.text2)
            .lineLimit(1)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.s1)
            .background(Tide.fill, in: .capsule)
            .accessibilityLabel("\(title) preview")
    }
}

// MARK: - OnboardingPreviewFrame

/// A glass card that carries a small live preview of the feature a
/// permission step is asking for, tagged as sample data.
struct OnboardingPreviewFrame<Content: View>: View {
    let title: String
    var tag = "Sample"
    @ViewBuilder var content: Content

    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            // Title and tag side by side; one over the other at accessibility
            // sizes so the title is never cut.
            let header = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s2))
            header {
                Text(title).tideLabel()
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(Tide.labelShrink)
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)
                }
                OnboardingSampleTag(title: tag)
            }
            content
        }
        .tideCard(padding: Tide.s4, radius: Tide.cardRadius)
    }
}

// MARK: - OnboardingMetricTile

/// One live figure: a symbol, a number that counts up, a level bar that
/// fills and a caption. Used in the previews of the health steps.
struct OnboardingMetricTile: View {
    let systemImage: String
    let value: String
    var unit: String?
    /// 0...1.
    let progress: Double
    let caption: String
    var tint: Color?
    /// Flips to true once the step has settled in, so the bar fills.
    let filled: Bool

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        let color = tint ?? mood.accent
        VStack(alignment: .leading, spacing: Tide.s2) {
            Image(systemName: systemImage)
                .font(Tide.bodyStrong)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            TideNumber(value, unit: unit, size: Tide.numeralS + Tide.s2, relativeTo: .title2, color: Tide.text)
            TideLevelBar(progress: filled ? progress : 0, color: color, height: Tide.barSlim)
                .background(Tide.fill, in: .capsule)
                .accessibilityHidden(true)
            Text(caption)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Tide.s3)
        .background(Tide.fill, in: .rect(cornerRadius: Tide.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - OnboardingBanner

/// A sample notification: the app tile, a title, a line and a time, drawn like
/// the banner it previews.
struct OnboardingBanner: View {
    let title: String
    let message: String
    var time = "now"

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Image(systemName: "bolt.fill")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.ink)
                .frame(width: Tide.tile, height: Tide.tile)
                .background(mood.accent, in: .rect(cornerRadius: Tide.controlRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Tide.s2)
                    Text(time)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
                Text(message)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Tide.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: Tide.tileRadius))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - OnboardingCheckToggleStyle

/// A big square tick for the one consent that matters: the whole row is the
/// target, and the tick draws itself in the accent.
struct OnboardingCheckToggleStyle: ToggleStyle {
    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: Tide.s4) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(Tide.title)
                    .foregroundStyle(configuration.isOn ? mood.accent : Tide.text3)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: reduceMotion ? false : configuration.isOn)
                    .accessibilityHidden(true)
                configuration.label
                Spacer(minLength: 0)
            }
            .frame(minHeight: Tide.hit)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == OnboardingCheckToggleStyle {
    static var onboardingCheck: OnboardingCheckToggleStyle {
        OnboardingCheckToggleStyle()
    }
}
