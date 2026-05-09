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

    @Query(sort: \DailyAccountability.date)
    private var allAccountability: [DailyAccountability]

    @State
    private var shareImage: StreakShareImage?

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.xxl) {
                // Streak stats header
                streakStatsHeader
                    .padding(.horizontal, TempoSpacing.screenEdge)

                // 7-day streak dots
                currentWeekDots
                    .padding(.horizontal, TempoSpacing.screenEdge)

                // 365-day heatmap
                heatmapSection
                    .padding(.horizontal, TempoSpacing.screenEdge)

                // Streak freeze info
                freezeSection
                    .padding(.horizontal, TempoSpacing.screenEdge)

                // Milestones
                milestonesSection
                    .padding(.horizontal, TempoSpacing.screenEdge)

                Spacer().frame(height: TempoSpacing.bottomSafe + 60)
            }
            .padding(.top, TempoSpacing.lg)
        }
        .background(Color.tempoBgPrimary)
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
        .sheet(item: $shareImage) { image in
            StreakShareSheet(items: [image.uiImage])
        }
    }

    // MARK: - Streak Stats Header

    private var streakStatsHeader: some View {
        HStack(spacing: TempoSpacing.lg) {
            // Current streak
            VStack(spacing: TempoSpacing.xs) {
                Text("\(viewModel.streakCount)")
                    .font(.tempoScoreDisplaySmall)
                    .foregroundStyle(Color.tempoSuccess)

                Text("Current Streak")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TempoSpacing.lg)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

            // Longest streak
            VStack(spacing: TempoSpacing.xs) {
                Text("\(viewModel.longestStreak)")
                    .font(.tempoScoreDisplaySmall)
                    .foregroundStyle(Color.tempoAmber)

                Text("Longest Streak")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TempoSpacing.lg)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
    }

    // MARK: - Current Week Dots

    private var currentWeekDots: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("THIS WEEK")
                .font(.tempoCaption2)
                .tracking(TempoTracking.caption2)
                .foregroundStyle(Color.tempoTextTertiary)

            HStack(spacing: TempoSpacing.md) {
                StreakDotsView(days: currentWeekStatuses)
                Spacer()
                if viewModel.isStreakAtRisk {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tempoAmber)
                        Text("AT RISK")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoAmber)
                    }
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("365-DAY HISTORY")
                .font(.tempoCaption2)
                .tracking(TempoTracking.caption2)
                .foregroundStyle(Color.tempoTextTertiary)

            HeatmapCalendarView(data: heatmapData)
                .padding(TempoSpacing.cardPadding)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
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
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("STREAK FREEZES")
                .font(.tempoCaption2)
                .tracking(TempoTracking.caption2)
                .foregroundStyle(Color.tempoTextTertiary)

            HStack(spacing: TempoSpacing.lg) {
                let freezesRemaining = (viewModel.overallStreak?.freezesAvailable ?? 2)
                    - (viewModel.overallStreak?.freezesUsed ?? 0)

                // Freeze icons
                HStack(spacing: TempoSpacing.sm) {
                    ForEach(0 ..< (viewModel.overallStreak?.freezesAvailable ?? 2), id: \.self) { index in
                        Image(systemName: index < freezesRemaining ? "snowflake" : "snowflake")
                            .font(.system(size: 24))
                            .foregroundStyle(
                                index < freezesRemaining
                                    ? Color.tempoElectric
                                    : Color.tempoTextTertiary.opacity(0.3)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text("\(max(0, freezesRemaining)) freezes remaining")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text("Freezes protect your streak on missed days. Resets monthly.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                Spacer()
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
    }

    // MARK: - Milestones Section

    // Per STATE_MACHINES.md Section 7 — milestone system.

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("MILESTONES")
                .font(.tempoCaption2)
                .tracking(TempoTracking.caption2)
                .foregroundStyle(Color.tempoTextTertiary)

            VStack(spacing: 0) {
                ForEach(StreakMilestone.allCases, id: \.rawValue) { milestone in
                    milestoneRow(milestone)

                    if milestone != StreakMilestone.allCases.last {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .padding(.vertical, TempoSpacing.xs)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
    }

    private func milestoneRow(_ milestone: StreakMilestone) -> some View {
        let achieved = viewModel.streakCount >= milestone.rawValue
        let isNext = !achieved && (
            StreakMilestone.allCases.first(where: { $0.rawValue > viewModel.streakCount })
                == milestone
        )

        return HStack(spacing: TempoSpacing.md) {
            // Icon
            Image(systemName: achieved ? "trophy.fill" : "trophy")
                .font(.system(size: 20))
                .foregroundStyle(achieved ? Color.tempoAmber : Color.tempoTextTertiary)
                .frame(width: 40)

            // Text
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(milestone.title)
                    .font(.tempoHeadline)
                    .foregroundStyle(achieved ? Color.tempoTextPrimary : Color.tempoTextTertiary)

                if milestone.xpBonus > 0 {
                    Text("+\(milestone.xpBonus) XP")
                        .font(.tempoCaption1)
                        .foregroundStyle(achieved ? Color.tempoElectric : Color.tempoTextTertiary)
                }

                if milestone.grantsBonusHour {
                    Text("Grants bonus hour (PS5 time 1h earlier)")
                        .font(.tempoCaption1)
                        .foregroundStyle(achieved ? Color.tempoSuccess : Color.tempoTextTertiary)
                }
            }

            Spacer()

            // Status
            if achieved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.tempoSuccess)
            } else if isNext {
                Text("\(milestone.rawValue - viewModel.streakCount) to go")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(.horizontal, TempoSpacing.cardPadding)
        .padding(.vertical, TempoSpacing.md)
        .opacity(achieved ? 1.0 : 0.6)
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

private struct StreakShareCard: View {
    let currentStreak: Int
    let longestStreak: Int
    let month: [(day: Int, completion: Double)]
    let weeklyConsistency: Double

    var body: some View {
        VStack(spacing: 48) {
            VStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(Color.orange)
                Text("\(currentStreak)")
                    .font(.system(size: 200, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("DAY STREAK")
                    .font(.system(size: 44, weight: .bold))
                    .tracking(8)
                    .foregroundStyle(.white.opacity(0.8))
            }

            VStack(spacing: 12) {
                HStack(spacing: 24) {
                    statTile(label: "LONGEST", value: "\(longestStreak)d")
                    statTile(label: "THIS WEEK", value: "\(Int(weeklyConsistency * 100))%")
                }
                monthHeatmap
            }
            .padding(40)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))

            Text("Tracked with Tempo")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(64)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 24, weight: .semibold))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var monthHeatmap: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(month, id: \.day) { item in
                RoundedRectangle(cornerRadius: 6)
                    .fill(cellColor(item.completion))
                    .frame(height: 56)
            }
        }
    }

    private func cellColor(_ completion: Double) -> Color {
        if completion >= 0.99 {
            return Color.green
        }
        if completion >= 0.5 {
            return Color.green.opacity(0.6)
        }
        if completion > 0 {
            return Color.orange.opacity(0.5)
        }
        return Color.white.opacity(0.08)
    }
}
