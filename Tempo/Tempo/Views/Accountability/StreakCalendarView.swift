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
            heatmapSection
            freezeSection
            milestonesSection
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
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Current streak").tideLabel()
                Spacer(minLength: Tide.s2)
                if viewModel.isStreakAtRisk {
                    TideStatusPill(text: "At risk", tint: TideTone.amber, systemImage: "exclamationmark.triangle.fill")
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                Image(systemName: "flame.fill")
                    .font(Tide.title)
                    .foregroundStyle(viewModel.streakCount > 0 ? Tide.streak : Tide.text3)
                    .accessibilityHidden(true)
                TideNumber(
                    "\(viewModel.streakCount)",
                    unit: viewModel.streakCount == 1 ? "day" : "days",
                    size: Tide.numeralHero,
                    relativeTo: .largeTitle,
                    color: viewModel.streakCount > 0 ? Tide.text : Tide.text2
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current streak, \(viewModel.streakCount) \(viewModel.streakCount == 1 ? "day" : "days")")

            if let next = nextMilestone {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    TideLevelBar(progress: progress(toward: next), color: Tide.streak)
                    HStack {
                        Text(next.title).font(Tide.caption).foregroundStyle(Tide.text2)
                        Spacer(minLength: Tide.s2)
                        Text("\(next.rawValue - viewModel.streakCount) to go")
                            .font(Tide.numeral(Tide.numeralS - Tide.s1, .semibold))
                            .foregroundStyle(Tide.text)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Every milestone cleared.").font(Tide.caption).foregroundStyle(Tide.text2)
            }

            TideDivider()

            HStack(alignment: .firstTextBaseline) {
                Text("Longest streak").font(Tide.body).foregroundStyle(Tide.text2)
                Spacer(minLength: Tide.s2)
                TideNumber(
                    "\(viewModel.longestStreak)",
                    unit: viewModel.longestStreak == 1 ? "day" : "days",
                    size: Tide.numeralM,
                    relativeTo: .title,
                    color: TideTone.amber
                )
            }
            .accessibilityElement(children: .combine)
        }
        .tideCard()
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
            TideSectionLabel(title: "This week")

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
            TideSectionLabel(title: "365-day history")

            TideHeatmap(data: heatmapData)
                .tideCard(padding: Tide.s4)
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
            TideSectionLabel(title: "Streak freezes")

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
                    Text("\(remaining) freezes remaining")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text("Freezes protect your streak on missed days. Resets monthly.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
            .tideCard(padding: Tide.s4)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Milestones Section

    // Per STATE_MACHINES.md Section 7 — milestone system.

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Milestones")

            VStack(spacing: 0) {
                ForEach(StreakMilestone.allCases, id: \.rawValue) { milestone in
                    milestoneRow(milestone)

                    if milestone != StreakMilestone.allCases.last {
                        TideDivider().padding(.leading, Tide.s4)
                    }
                }
            }
            .tideCard(padding: 0)
        }
    }

    private func milestoneRow(_ milestone: StreakMilestone) -> some View {
        let achieved = viewModel.streakCount >= milestone.rawValue
        let isNext = milestone == nextMilestone

        return HStack(spacing: Tide.s3) {
            TideAreaIconTile(
                systemName: achieved ? "trophy.fill" : "trophy",
                tint: achieved ? TideTone.gold : Tide.text3
            )

            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(milestone.title)
                    .font(Tide.headline)
                    .foregroundStyle(achieved ? Tide.text : Tide.text2)

                if milestone.xpBonus > 0 {
                    Text("+\(milestone.xpBonus) XP")
                        .font(Tide.caption)
                        .foregroundStyle(achieved ? mood.accent : Tide.text3)
                }

                if milestone.grantsBonusHour {
                    Text("Grants bonus hour (PS5 time 1h earlier)")
                        .font(Tide.caption)
                        .foregroundStyle(achieved ? TideTone.mint : Tide.text3)
                }
            }

            Spacer(minLength: Tide.s2)

            if achieved {
                Image(systemName: "checkmark.circle.fill")
                    .font(Tide.title2)
                    .foregroundStyle(TideTone.mint)
                    .accessibilityLabel("Reached")
            } else if isNext {
                TideStatusPill(text: "\(milestone.rawValue - viewModel.streakCount) to go", tint: mood.accent)
            }
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(minHeight: Tide.hit)
        .opacity(achieved || isNext ? 1 : 0.6)
        .accessibilityElement(children: .combine)
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
        .frame(width: 1080, height: 1350)
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

    var body: some View {
        VStack(spacing: 56) {
            VStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(Tide.numeral(120, .bold))
                    .foregroundStyle(Tide.streak)
                Text("\(currentStreak)")
                    .font(Tide.numeral(280, .heavy))
                    .foregroundStyle(Tide.text)
                Text("DAY STREAK")
                    .font(Tide.numeral(44, .bold))
                    .tracking(10)
                    .foregroundStyle(Tide.text2)
            }

            VStack(spacing: 24) {
                HStack(spacing: 24) {
                    statTile(label: "LONGEST", value: "\(longestStreak)d")
                    statTile(label: "THIS WEEK", value: "\(Int(weeklyConsistency * 100))%")
                }
                monthHeatmap
            }
            .padding(40)
            .background(Tide.fill, in: .rect(cornerRadius: 40, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .strokeBorder(Tide.hairline, lineWidth: 2)
            )

            Text("TRACKED WITH TEMPO")
                .font(Tide.numeral(26, .semibold))
                .tracking(6)
                .foregroundStyle(Tide.text3)
        }
        .padding(64)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                Tide.ink
                RadialGradient(
                    colors: [Tide.streak.opacity(0.32), .clear],
                    center: .init(x: 0.5, y: 0.18),
                    startRadius: 0,
                    endRadius: 760
                )
            }
        )
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(Tide.numeral(24, .semibold))
                .tracking(5)
                .foregroundStyle(Tide.text3)
            Text(value)
                .font(Tide.numeral(88, .bold))
                .foregroundStyle(Tide.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var monthHeatmap: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(month, id: \.day) { item in
                RoundedRectangle(cornerRadius: 8)
                    .fill(cellColor(item.completion))
                    .frame(height: 56)
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
