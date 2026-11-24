//
// Tide+Lockdown.swift
// Tempo
//
// Lockdown's own Tide pieces: the week of streak days and the 365-day
// history grid. They take the same data as the older shared views but draw it
// in Tide colours, with room for a finger.
//

import SwiftUI

// MARK: - Pinned bar scrim

extension View {
    /// The ink fade behind a bar pinned to the bottom of a scrolling page, so
    /// the content that scrolls under it never reads through the buttons.
    /// It runs on past the home indicator and starts a little above the bar.
    func lockdownPinnedScrim() -> some View {
        background {
            LinearGradient(
                colors: [.clear, Tide.ink.opacity(0.85), Tide.ink.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -Tide.s6)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - TideStreakDots

/// One column per day of the week, Monday first: a letter above a disc that is
/// lit when the day was completed, ringed when it was missed, and carries the
/// mood colour for today.
struct TideStreakDots: View {
    let days: [StreakDotsView.DayStatus]

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .body)
    private var disc: CGFloat = 32

    /// Seven discs share one row, so they stop growing before the row outgrows the screen.
    private var discSize: CGFloat {
        min(disc, Tide.avatar)
    }

    var body: some View {
        HStack(spacing: Tide.s1) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, status in
                VStack(spacing: Tide.s2) {
                    Text(Self.shortName(index)).tideLabel(Tide.text3)
                    dot(status)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(Self.fullName(index)), \(spoken(status))")
            }
        }
        .animation(Tide.snap, value: days.map(\.isCompleted))
    }

    @ViewBuilder
    private func dot(_ status: StreakDotsView.DayStatus) -> some View {
        switch status {
        case .completed:
            lit
        case .missed:
            Circle()
                .fill(Tide.danger.opacity(0.16))
                .overlay(Circle().strokeBorder(Tide.danger.opacity(0.55), lineWidth: Tide.rule))
                .overlay(Image(systemName: "xmark").font(Tide.label).foregroundStyle(Tide.danger))
                .frame(width: discSize, height: discSize)
        case let .today(completed):
            if completed {
                lit
            } else {
                Circle()
                    .fill(mood.accent.opacity(0.14))
                    .overlay(Circle().strokeBorder(mood.accent, lineWidth: Tide.hair))
                    .overlay(Circle().fill(mood.accent).frame(width: Tide.s2, height: Tide.s2))
                    .frame(width: discSize, height: discSize)
            }
        case .future:
            Circle()
                .strokeBorder(Tide.hairline, lineWidth: Tide.rule)
                .frame(width: discSize, height: discSize)
        }
    }

    private var lit: some View {
        Circle()
            .fill(TideTone.mint)
            .overlay(Image(systemName: "checkmark").font(Tide.label).foregroundStyle(Tide.ink))
            .frame(width: discSize, height: discSize)
    }

    private func spoken(_ status: StreakDotsView.DayStatus) -> String {
        switch status {
        case .completed: "completed"
        case .missed: "missed"
        case let .today(completed): completed ? "today, completed" : "today, in progress"
        case .future: "upcoming"
        }
    }

    /// Monday-first single letters ("M", "T", ...), in the user's language.
    private static func shortName(_ index: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols[(index + 1) % 7]
    }

    private static func fullName(_ index: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[(index + 1) % 7]
    }
}

// MARK: - TideHeatmap

/// A year of days as a grid of weeks, lit mint by how much of the day was done.
/// Cells are big enough to read and tap: the grid scrolls sideways and opens on
/// the most recent weeks. Tap a day for its figure.
struct TideHeatmap: View {
    let data: [Date: Double]
    let startDate: Date
    let endDate: Date

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .caption2)
    private var labelHeight: CGFloat = 14
    @State
    private var selectedDate: Date?

    private let cell: CGFloat = Tide.s3
    private let gap: CGFloat = Tide.s1 - Tide.rule
    private let dayLabelWidth: CGFloat = Tide.s5

    init(data: [Date: Double], startDate: Date? = nil, endDate: Date? = nil) {
        self.data = data
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: endDate ?? Date())
        self.endDate = end
        self.startDate = startDate ?? calendar.date(byAdding: .day, value: -364, to: end) ?? end
    }

    // MARK: Geometry

    private var step: CGFloat {
        cell + gap
    }

    /// The first day of the week that holds `startDate`, so rows are weekdays.
    private var gridStart: Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: startDate)
        let back = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: startDate) ?? startDate
    }

    private var dayCount: Int {
        max(0, (Calendar.current.dateComponents([.day], from: gridStart, to: endDate).day ?? 0) + 1)
    }

    private var weekCount: Int {
        (dayCount + 6) / 7
    }

    private var gridWidth: CGFloat {
        CGFloat(weekCount) * step - gap
    }

    private var gridHeight: CGFloat {
        7 * step - gap
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .top, spacing: Tide.s1) {
                dayLabels

                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        monthLabels
                        grid
                    }
                    .padding(.trailing, Tide.hair)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing)
            }

            footer
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("History, last \(dayCount) days")
        .accessibilityValue(spokenSummary)
    }

    private var dayLabels: some View {
        VStack(spacing: gap) {
            Color.clear.frame(width: dayLabelWidth, height: labelHeight + Tide.s1)
            ForEach(0 ..< 7, id: \.self) { row in
                Text(row.isMultiple(of: 2) ? dayLabel(row) : "")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: dayLabelWidth, height: cell, alignment: .trailing)
            }
        }
        .accessibilityHidden(true)
    }

    private var monthLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthMarks, id: \.week) { mark in
                Text(mark.label)
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .fixedSize()
                    .offset(x: CGFloat(mark.week) * step)
            }
        }
        .frame(width: gridWidth, height: labelHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var grid: some View {
        Canvas { context, _ in
            let calendar = Calendar.current
            for offset in 0 ..< dayCount {
                guard let day = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                    continue
                }
                if day < startDate {
                    continue
                }
                let column = offset / 7
                let row = offset % 7
                let rect = CGRect(
                    x: CGFloat(column) * step,
                    y: CGFloat(row) * step,
                    width: cell,
                    height: cell
                )
                let path = Path(roundedRect: rect, cornerRadius: Tide.hair)
                let value = data[calendar.startOfDay(for: day)] ?? 0
                context.fill(path, with: .color(color(for: value)))

                if calendar.isDateInToday(day) {
                    context.stroke(path, with: .color(Tide.text), lineWidth: Tide.rule)
                }
                if let selectedDate, calendar.isDate(day, inSameDayAs: selectedDate) {
                    context.stroke(path, with: .color(mood.accent), lineWidth: Tide.hair)
                }
            }
        }
        .frame(width: gridWidth, height: gridHeight)
        .contentShape(.rect)
        .gesture(
            SpatialTapGesture()
                .onEnded { tap in
                    let picked = date(at: tap.location)
                    withAnimation(Tide.snap) {
                        selectedDate = picked == selectedDate ? nil : picked
                    }
                }
        )
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    @ViewBuilder
    private var footer: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))

        layout {
            tooltip
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: Tide.s2)
            }
            legend
        }
    }

    @ViewBuilder
    private var tooltip: some View {
        if let selectedDate {
            let value = data[Calendar.current.startOfDay(for: selectedDate)] ?? 0
            HStack(spacing: Tide.s2) {
                Text(selectedDate, format: .dateTime.month(.abbreviated).day().year())
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                Text("\(Int((value * 100).rounded()))%")
                    .font(Tide.numeral(Tide.numeralS - Tide.s1, .bold))
                    .foregroundStyle(Tide.text)
            }
        } else {
            Text("Tap a day").font(Tide.caption).foregroundStyle(Tide.text3)
        }
    }

    private var legend: some View {
        HStack(spacing: Tide.s1) {
            Text("Less").font(Tide.label).foregroundStyle(Tide.text3)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: Tide.hair)
                    .fill(color(for: level))
                    .frame(width: cell, height: cell)
            }
            Text("More").font(Tide.label).foregroundStyle(Tide.text3)
        }
    }

    // MARK: Helpers

    private func color(for value: Double) -> Color {
        guard value > 0 else {
            return Tide.fill
        }
        switch value {
        case ...0.25: return TideTone.mint.opacity(0.30)
        case ...0.50: return TideTone.mint.opacity(0.52)
        case ...0.75: return TideTone.mint.opacity(0.76)
        default: return TideTone.mint
        }
    }

    private func date(at point: CGPoint) -> Date? {
        let column = Int(point.x / step)
        let row = Int(point.y / step)
        guard row >= 0, row < 7, column >= 0 else {
            return nil
        }
        let calendar = Calendar.current
        guard let day = calendar.date(byAdding: .day, value: column * 7 + row, to: gridStart),
              day >= startDate, day <= endDate
        else {
            return nil
        }
        return calendar.startOfDay(for: day)
    }

    private func dayLabel(_ row: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols[(row + Calendar.current.firstWeekday - 1) % 7]
    }

    /// The column where each month's first week starts.
    private var monthMarks: [(week: Int, label: String)] {
        let calendar = Calendar.current
        var marks: [(week: Int, label: String)] = []
        var lastMonth = -1
        for week in 0 ..< weekCount {
            guard let day = calendar.date(byAdding: .day, value: week * 7, to: gridStart) else {
                continue
            }
            let month = calendar.component(.month, from: day)
            if month != lastMonth {
                marks.append((week, day.formatted(.dateTime.month(.abbreviated))))
                lastMonth = month
            }
        }
        // A month label squeezed against the next one is unreadable: drop it.
        return marks.enumerated().compactMap { index, mark in
            let next = index + 1 < marks.count ? marks[index + 1].week : weekCount
            return next - mark.week >= 3 ? mark : nil
        }
    }

    private var spokenSummary: String {
        let full = data.values.filter { $0 >= 0.99 }.count
        return "\(full) full days"
    }
}

// MARK: - LockdownSessionDots

/// The focus-timer's sessions as a row of dots: lit for each finished session,
/// ringed for the one in progress, empty for the rest.
struct LockdownSessionDots: View {
    /// Sessions already finished in this run.
    let completed: Int
    /// Sessions before the long break.
    let total: Int
    /// Whether a session is running right now (the next dot is ringed).
    let running: Bool

    @Environment(\.tideMood)
    private var mood
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        HStack(spacing: Tide.s2) {
            ForEach(0 ..< max(total, 1), id: \.self) { index in
                dot(index)
            }
        }
        .animation(reduceMotion ? nil : Tide.snap, value: completed)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func dot(_ index: Int) -> some View {
        if index < completed {
            Circle().fill(mood.accent).frame(width: Tide.s2, height: Tide.s2)
        } else if index == completed, running {
            Circle()
                .strokeBorder(mood.accent, lineWidth: Tide.hair)
                .frame(width: Tide.s2, height: Tide.s2)
                .overlay(Circle().fill(mood.accent.opacity(0.35)))
        } else {
            Circle().fill(Tide.track).frame(width: Tide.s2, height: Tide.s2)
        }
    }
}

// MARK: - LockdownSeal

/// A ring that draws itself closed around a symbol: the stamp that ends a moment.
/// Reduce Motion shows it already closed.
struct LockdownSeal: View {
    let systemImage: String
    var tint: Color = TideTone.mint
    var diameter: CGFloat = Tide.dialDetail

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var sealed = false

    var body: some View {
        ZStack {
            Circle().stroke(Tide.track, lineWidth: Tide.bar)
            Circle()
                .trim(from: 0, to: sealed ? 1 : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: Tide.bar, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.6), radius: Tide.s4)
            Image(systemName: systemImage)
                .font(Tide.numeral(Tide.numeralL, .semibold))
                .foregroundStyle(tint)
                .scaleEffect(sealed ? 1 : 0.4)
                .opacity(sealed ? 1 : 0)
                .symbolEffect(.bounce, value: sealed)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                sealed = true
            } else {
                withAnimation(Tide.lively.delay(0.2)) { sealed = true }
            }
        }
    }
}

// MARK: - LockdownUnlockMoment

/// The full-screen moment when the day's non-negotiables are done and leisure
/// unlocks: a burst, the lock opening, the day's score rising into place, and
/// one button under the thumb. It scrolls only when the text is too large.
struct LockdownUnlockMoment: View {
    /// The day's score, when there is one to show.
    let score: Int?
    /// The current streak in days (0 hides the pill).
    let streak: Int
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var opened = false
    @State
    private var risen = false

    var body: some View {
        ZStack {
            // The page stays faintly visible behind the moment.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Tide.ink.opacity(0.55))
                .ignoresSafeArea()
                .onTapGesture(perform: onContinue)

            ArenaBurst(accent: TideTone.mint)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Tide.s4) {
                        Spacer(minLength: Tide.s6)

                        hero
                            .scaleEffect(risen ? 1 : 0.6)
                            .opacity(risen ? 1 : 0)

                        HStack(spacing: Tide.s2) {
                            Image(systemName: opened ? "lock.open.fill" : "lock.fill")
                                .contentTransition(.symbolEffect(.replace))
                                .accessibilityHidden(true)
                            Text("PS5 unlocked")
                        }
                        .font(Tide.title)
                        .foregroundStyle(TideTone.mint)
                        .multilineTextAlignment(.center)
                        // Each line follows the one before, after the score has landed.
                        .arenaReveal(5)

                        Text("You earned it. Enjoy your evening.")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .arenaReveal(7)

                        if streak > 0 {
                            TideStatusPill(text: "Day \(streak)", tint: TideTone.amber, systemImage: "flame.fill")
                                .arenaReveal(9)
                        }

                        Spacer(minLength: Tide.s6)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, Tide.edge)
                    // The scroll view covers the backdrop, so a tap anywhere on
                    // the moment (not only the Continue button) closes it. A
                    // drag still scrolls.
                    .contentShape(.rect)
                    .onTapGesture(perform: onContinue)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Continue", action: onContinue)
                    .buttonStyle(.tidePrimary)
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s2)
                    .padding(.bottom, Tide.s2)
                    .lockdownPinnedScrim()
            }
        }
        // The unlock itself already buzzes (triple success), so the lock opens silently.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onContinue)
        .task {
            if reduceMotion {
                risen = true
                opened = true
                return
            }
            withAnimation(Tide.lively) { risen = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(Tide.lively) { opened = true }
        }
    }

    /// The day's score when there is one; otherwise the open lock itself.
    @ViewBuilder
    private var hero: some View {
        if let score {
            // The dial's caption has no room to wrap: the same short caption as
            // Today's dial, and shorter still at large text.
            TideDial(
                score: score,
                caption: typeSize.isAccessibilitySize ? "Score" : "Day score",
                diameter: Tide.dialHero
            )
            .accessibilityElement(children: .combine)
        } else {
            LockdownSeal(systemImage: "lock.open.fill", diameter: Tide.dialHero)
        }
    }
}

// MARK: - LockdownShareMetric

/// Sizes of the streak picture people post. It is drawn offscreen at a fixed
/// 1080 x 1350 export, so these are export pixels, not layout tokens: they do
/// not scale with Dynamic Type or the screen.
enum LockdownShareMetric {
    static let width: CGFloat = 1080
    static let height: CGFloat = 1350
    static let outer: CGFloat = 64
    static let stack: CGFloat = 56
    static let inner: CGFloat = 24
    static let tight: CGFloat = 8
    static let flame: CGFloat = 120
    static let count: CGFloat = 280
    static let caption: CGFloat = 44
    static let captionTracking: CGFloat = 10
    static let panelPad: CGFloat = 40
    static let panelRadius: CGFloat = 40
    static let rule: CGFloat = 2
    static let footer: CGFloat = 26
    static let footerTracking: CGFloat = 6
    static let glowRadius: CGFloat = 760
    static let statLabel: CGFloat = 24
    static let statTracking: CGFloat = 5
    static let statValue: CGFloat = 88
    static let statPad: CGFloat = 16
    static let cellGap: CGFloat = 10
    static let cellHeight: CGFloat = 56
    static let cellRadius: CGFloat = 8
}
