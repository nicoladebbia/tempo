//
// StreakCalendarView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI
import UIKit

// MARK: - StreakCalendarView

// Per BUILD_PLAN step 10.6.
// Per MODULE_ACCOUNTABILITY.md — Streaks section.
// Per STATE_MACHINES.md Section 7 — Streak state machine.

struct StreakCalendarView: View {
    @Bindable
    var viewModel: AccountabilityViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.tideMood)
    private var mood

    @Query(sort: \DailyAccountability.date)
    private var allAccountability: [DailyAccountability]

    @State
    private var shareImage: StreakShareImage?

    var body: some View {
        TideScrollPage(spacing: Tide.s6, spacer: Tide.s2) {
            streakHero
            currentWeekDots
            milestonesSection
            freezeSection
            heatmapSection
        }
        .navigationTitle("Streak")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    generateShareImage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share streak")
            }
        }
        .tideCovered(shareImage != nil)
        .sheet(item: $shareImage) { image in
            StreakShareSheet(items: [image.uiImage])
        }
    }

    // MARK: - Streak Hero

    private var nextMilestone: StreakMilestone? {
        StreakMilestone.allCases.first { $0.rawValue > viewModel.streakCount }
    }

    private var streakHero: some View {
        let count = viewModel.streakCount
        let dayText = String(localized: "\(count) days")

        return RecoveryHero {
            // The ring fills toward the next milestone, lit like the focus dial.
            TideTimerDial(
                progress: nextMilestone.map { progress(toward: $0) } ?? 1,
                accent: count > 0 ? Tide.streak : Tide.text3,
                diameter: Tide.dialHero
            ) {
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(Tide.headline)
                        .foregroundStyle(count > 0 ? Tide.streak : Tide.text3)
                        .symbolEffect(.pulse, isActive: viewModel.isStreakAtRisk)
                        .accessibilityHidden(true)
                    TideNumber(
                        "\(count)",
                        size: Tide.numeralL,
                        relativeTo: .title,
                        color: count > 0 ? Tide.text : Tide.text2
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current streak, \(dayText)")
            .explains(Explainer.currentStreak.showing(dayText))
        } side: {
            Text("Current streak").tideLabel()

            Text(dayText)
                .font(Tide.title2)
                .foregroundStyle(count > 0 ? Tide.streak : Tide.text2)
                .accessibilityHidden(true)

            // Its own line: beside the label there was no room and it was cut to "AT R…".
            if viewModel.isStreakAtRisk {
                TideStatusPill(text: String(localized: "At risk"), tint: TideTone.amber, systemImage: "exclamationmark.triangle.fill")
            }

            if let next = nextMilestone {
                HStack(alignment: .firstTextBaseline) {
                    Text(next.title).font(Tide.caption).foregroundStyle(Tide.text2)
                    Spacer(minLength: Tide.s2)
                    TideNumber(
                        String(localized: "\(next.rawValue - count) to go"),
                        size: Tide.numeralS - Tide.s1,
                        relativeTo: .headline,
                        weight: .semibold
                    )
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Every milestone cleared.").font(Tide.caption).foregroundStyle(Tide.text2)
            }

            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text("Longest streak").font(Tide.caption).foregroundStyle(Tide.text2)
                Spacer(minLength: Tide.s2)
                TideNumber(
                    "\(viewModel.longestStreak)",
                    unit: viewModel.longestStreak == 1 ? String(localized: "day") : String(localized: "days"),
                    size: Tide.numeralS,
                    relativeTo: .headline,
                    color: TideTone.amber
                )
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// How far the streak has come between the last milestone reached and the next one.
    private func progress(toward next: StreakMilestone) -> Double {
        let previous = StreakMilestone.allCases.last { $0.rawValue <= viewModel.streakCount }?.rawValue ?? 0
        let span = Double(next.rawValue - previous)
        guard span > 0 else {
            return 0
        }
        return min(1, max(0, Double(viewModel.streakCount - previous) / span))
    }

    // MARK: - Current Week Dots

    private var currentWeekDots: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "This week"))

            TideStreakDots(days: currentWeekStatuses)
                .tideCard(padding: Tide.s4)
        }
    }

    private var currentWeekStatuses: [StreakDotsView.DayStatus] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        // Monday = start of week
        let mondayOffset = (weekday - 2 + 7) % 7
        let monday = calendar.date(byAdding: .day, value: -mondayOffset, to: today)!

        return (0 ..< 7).map { dayIndex in
            let date = calendar.date(byAdding: .day, value: dayIndex, to: monday)!
            let dayStart = calendar.startOfDay(for: date)

            if dayStart > today {
                return .future
            }

            if calendar.isDateInToday(date) {
                let todayComplete = viewModel.accountability?.allComplete ?? false
                return .today(completed: todayComplete)
            }

            // Check if this day was completed
            let dayAccountability = allAccountability.first { da in
                calendar.isDate(da.date, inSameDayAs: date)
            }

            if let da = dayAccountability, da.allComplete {
                return .completed
            }

            return .missed
        }
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "365-day history"))

            TideHeatmap(data: heatmapData)
                .tideCard(padding: Tide.s4)
                .explains(.streakHistory)
        }
    }

    private var heatmapData: [Date: Double] {
        var data: [Date: Double] = [:]
        let calendar = Calendar.current

        for da in allAccountability {
            let dayStart = calendar.startOfDay(for: da.date)
            // Normalize score to 0-1 range (score is 0-100)
            data[dayStart] = Double(da.accountabilityScore) / 100.0
        }

        return data
    }

    // MARK: - Freeze Section

    // Per STATE_MACHINES.md Section 7 — freeze mechanics.

    private var freezeSection: some View {
        let available = viewModel.overallStreak?.freezesAvailable ?? 2
        let remaining = max(0, available - (viewModel.overallStreak?.freezesUsed ?? 0))
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s4))

        return VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "Streak freezes"))

            layout {
                HStack(spacing: Tide.s2) {
                    ForEach(0 ..< available, id: \.self) { index in
                        Image(systemName: "snowflake")
                            .font(Tide.title2)
                            .foregroundStyle(index < remaining ? TideTone.sky : Tide.text3.opacity(0.4))
                    }
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(remaining == 1 ? String(localized: "1 freeze remaining") : String(localized: "\(remaining) freezes remaining"))
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text("Freezes protect your streak on missed days.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
            .tideCard(padding: Tide.s4)
            .accessibilityElement(children: .combine)
            .explains(.streakFreezes)
        }
    }

    // MARK: - Milestones Section

    // Per STATE_MACHINES.md Section 7 — milestone system.

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "Milestones"))

            VStack(spacing: 0) {
                ForEach(StreakMilestone.allCases, id: \.rawValue) { milestone in
                    milestoneRow(milestone, isLast: milestone == StreakMilestone.allCases.last)
                }
            }
            .tideCard(padding: Tide.s4)
            .explains(.streakMilestones)
        }
    }

    /// One stop on the path: a node on the rail, then what the stop is worth.
    private func milestoneRow(_ milestone: StreakMilestone, isLast: Bool) -> some View {
        let achieved = viewModel.streakCount >= milestone.rawValue
        let isNext = milestone == nextMilestone

        return HStack(alignment: .top, spacing: Tide.s3) {
            VStack(spacing: 0) {
                milestoneNode(achieved: achieved, isNext: isNext)
                if !isLast {
                    Rectangle()
                        .fill(achieved ? TideTone.mint.opacity(0.6) : Tide.hairline)
                        .frame(width: Tide.hair)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: Tide.icon)

            // The "to go" pill drops under the title at accessibility sizes.
            let textRow = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s2))
            textRow {
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(milestone.title)
                        .font(Tide.headline)
                        .foregroundStyle(achieved || isNext ? Tide.text : Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)

                    if milestone.xpBonus > 0 {
                        Text("+\(milestone.xpBonus) XP")
                            .font(Tide.caption)
                            .foregroundStyle(achieved ? mood.accent : Tide.text3)
                    }

                    if milestone.grantsBonusHour {
                        Text("Grants bonus hour (PS5 time 1h earlier)")
                            .font(Tide.caption)
                            .foregroundStyle(achieved ? TideTone.mint : Tide.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)
                }

                if isNext {
                    TideStatusPill(text: String(localized: "\(milestone.rawValue - viewModel.streakCount) to go"), tint: mood.accent)
                }
            }
            .padding(.bottom, isLast ? 0 : Tide.s4)
        }
        // Full width, so every node sits on the same rail whatever its text wraps to.
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
        .opacity(achieved || isNext ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityValue(achieved ? String(localized: "Reached") : "")
    }

    @ViewBuilder
    private func milestoneNode(achieved: Bool, isNext: Bool) -> some View {
        if achieved {
            Circle()
                .fill(TideTone.mint)
                .frame(width: Tide.icon, height: Tide.icon)
                .overlay(Image(systemName: "checkmark").font(Tide.label).foregroundStyle(Tide.ink))
        } else if isNext {
            Circle()
                .fill(mood.accent.opacity(0.16))
                .overlay(Circle().strokeBorder(mood.accent, lineWidth: Tide.hair))
                .overlay(Circle().fill(mood.accent).frame(width: Tide.s2, height: Tide.s2))
                .frame(width: Tide.icon, height: Tide.icon)
        } else {
            Circle()
                .strokeBorder(Tide.hairline, lineWidth: Tide.rule)
                .frame(width: Tide.icon, height: Tide.icon)
        }
    }

    // MARK: - Share Image

    /// Render a 1080×1350 PNG of the streak summary and present a share sheet.
    /// Per MODULE_ACCOUNTABILITY.md §5.7.
    @MainActor
    private func generateShareImage() {
        let view = StreakShareCard(
            currentStreak: viewModel.streakCount,
            longestStreak: viewModel.longestStreak,
            month: monthDays(for: Date()),
            weeklyConsistency: weeklyConsistencyFraction()
        )
        .frame(width: LockdownShareMetric.width, height: LockdownShareMetric.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        if let cg = renderer.cgImage {
            shareImage = StreakShareImage(uiImage: UIImage(cgImage: cg))
        }
    }

    private func weeklyConsistencyFraction() -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekStart = cal.date(byAdding: .day, value: -6, to: today) else {
            return 0
        }
        let recent = allAccountability.filter { $0.date >= weekStart && $0.date <= today }
        guard !recent.isEmpty else {
            return 0
        }
        let totalCompletion = recent.reduce(0.0) { $0 + $1.completionPercentage }
        return totalCompletion / Double(recent.count)
    }

    private func monthDays(for date: Date) -> [(day: Int, completion: Double)] {
        let cal = Calendar.current
        guard let monthInterval = cal.dateInterval(of: .month, for: date) else {
            return []
        }
        let dayCount = cal.range(of: .day, in: .month, for: date)?.count ?? 30
        var rows: [(day: Int, completion: Double)] = []
        for offset in 0 ..< dayCount {
            guard let day = cal.date(byAdding: .day, value: offset, to: monthInterval.start) else {
                continue
            }
            let match = allAccountability.first { cal.isDate($0.date, inSameDayAs: day) }
            rows.append((cal.component(.day, from: day), match?.completionPercentage ?? 0))
        }
        return rows
    }
}

// MARK: - StreakShareImage

struct StreakShareImage: Identifiable {
    let id = UUID()
    let uiImage: UIImage
}

// MARK: - StreakShareSheet

struct StreakShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

// MARK: - StreakShareCard

/// The picture people post. It is drawn offscreen at a fixed 1080×1350, so its
/// sizes are export pixels rather than layout tokens: a fixed palette (no mood,
/// no Dynamic Type) on the Tide ink, with the same condensed numerals as the app.
private struct StreakShareCard: View {
    let currentStreak: Int
    let longestStreak: Int
    let month: [(day: Int, completion: Double)]
    let weeklyConsistency: Double

    private typealias Px = LockdownShareMetric

    var body: some View {
        VStack(spacing: Px.stack) {
            VStack(spacing: Px.tight) {
                Image(systemName: "flame.fill")
                    .font(Tide.numeral(Px.flame, .bold))
                    .foregroundStyle(Tide.streak)
                Text("\(currentStreak)")
                    .font(Tide.numeral(Px.count, .heavy))
                    .foregroundStyle(Tide.text)
                Text("DAY STREAK")
                    .font(Tide.numeral(Px.caption, .bold))
                    .tracking(Px.captionTracking)
                    .foregroundStyle(Tide.text2)
            }

            VStack(spacing: Px.inner) {
                HStack(spacing: Px.inner) {
                    statTile(label: String(localized: "LONGEST"), value: String(localized: "\(longestStreak)d"))
                    statTile(label: String(localized: "THIS WEEK"), value: "\(Int(weeklyConsistency * 100))%")
                }
                monthHeatmap
            }
            .padding(Px.panelPad)
            .background(Tide.fill, in: .rect(cornerRadius: Px.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Px.panelRadius, style: .continuous)
                    .strokeBorder(Tide.hairline, lineWidth: Px.rule)
            )

            Text("TRACKED WITH TEMPO")
                .font(Tide.numeral(Px.footer, .semibold))
                .tracking(Px.footerTracking)
                .foregroundStyle(Tide.text3)
        }
        .padding(Px.outer)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Tide.ink
                RadialGradient(
                    colors: [Tide.streak.opacity(0.32), .clear],
                    center: .init(x: 0.5, y: 0.18),
                    startRadius: 0,
                    endRadius: Px.glowRadius
                )
            }
        )
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: Px.tight) {
            Text(label)
                .font(Tide.numeral(Px.statLabel, .semibold))
                .tracking(Px.statTracking)
                .foregroundStyle(Tide.text3)
            Text(value)
                .font(Tide.numeral(Px.statValue, .bold))
                .foregroundStyle(Tide.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Px.statPad)
    }

    private var monthHeatmap: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Px.cellGap), count: 7)
        return LazyVGrid(columns: columns, spacing: Px.cellGap) {
            ForEach(month, id: \.day) { item in
                RoundedRectangle(cornerRadius: Px.cellRadius)
                    .fill(cellColor(item.completion))
                    .frame(height: Px.cellHeight)
            }
        }
    }

    private func cellColor(_ completion: Double) -> Color {
        if completion >= 0.99 {
            return TideTone.mint
        }
        if completion >= 0.5 {
            return TideTone.mint.opacity(0.55)
        }
        if completion > 0 {
            return TideTone.amber.opacity(0.5)
        }
        return Tide.fill
    }
}
