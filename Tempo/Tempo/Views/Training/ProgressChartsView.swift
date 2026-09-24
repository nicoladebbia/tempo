//
// ProgressChartsView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import SwiftData
import SwiftUI

// MARK: - Progress Charts View

// Per MODULE_TRAINING.md Section 11 — Three tabs: Per Exercise, Muscle Groups, Overview.
// Per WIREFRAMES.md Screen 21 — Progress chart per exercise.

struct ProgressChartsView: View {
    /// modelContext intentionally removed — this view is now read-only. The
    /// only writer was the deleted purge; reintroducing context access here
    /// would invite another on-appearance mutation of history. Deletions
    /// happen in WorkoutHistoryView.
    @Query(sort: \ExerciseHistory.date, order: .reverse)
    private var allHistory: [ExerciseHistory]
    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]
    @Query(sort: \WorkoutPlan.date, order: .reverse)
    private var workoutPlans: [WorkoutPlan]
    @Query(sort: \ActivitySession.date, order: .reverse)
    private var activitySessions: [ActivitySession]
    @Query
    private var userSettings: [UserSettings]

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    @State
    private var selectedTab: ProgressTab = .overview

    enum ProgressTab: String, CaseIterable {
        case lab = "Lab"
        case overview = "Overview"
        case exercises = "Exercises"
        case muscles = "Muscles"
        case activity = "Activity"
    }

    private var hasAnyData: Bool {
        workoutPlans.contains(where: { $0.status == .completed })
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasAnyData {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No Progress Yet",
                    message: "Complete your first workout to start tracking progress."
                )
            } else {
                // Segmented picker
                // Per MODULE_TRAINING.md Section 11.1 — segmented control at top
                Picker("View", selection: $selectedTab) {
                    ForEach(ProgressTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.sm)

                ScrollView(.vertical, showsIndicators: false) {
                    switch selectedTab {
                    case .lab:
                        // §11.2 — the interactive Strength Lab (scrubbable
                        // e1RM curve, PR stars, compare lift, volume bars).
                        StrengthProgressLabView()
                    case .overview:
                        overviewTab
                    case .exercises:
                        exercisesTab
                    case .muscles:
                        muscleGroupsTab
                    case .activity:
                        activityTab
                    }
                }
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        // NOTE: there is deliberately NO orphan-purge on appearance. A prior
        // purgeOrphanedHistory() ran here and DELETED valid ExerciseHistory on
        // every Progress open whenever the matching WorkoutPlan wasn't marked
        // .completed — a data-loss bug. ExerciseHistory is the permanent
        // training record and is independent of the ephemeral daily
        // WorkoutPlan (no schema relationship); its validity is never derived
        // from plan status. Orphan cleanup happens only at explicit user
        // deletion in WorkoutHistoryView.deleteWorkout(), keyed by workoutPlanID.
    }

    // MARK: - Overview Tab

    // Per MODULE_TRAINING.md Section 11.4

    private var overviewTab: some View {
        VStack(spacing: TempoSpacing.xl) {
            // §11.8 — the week-in-motion hero: this week's volume, delta vs
            // last week, 8-week trend, streak + fresh PRs.
            thisWeekHero

            // Acute:chronic load vs the safety floor's limit.
            TrainingLoadCard()

            // All-time stats
            allTimeStats

            // Workout frequency
            workoutFrequencyCard

            // Body part split
            bodyPartSplitCard
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
    }

    // MARK: - This Week Hero (§11.8)

    /// Trailing 8 ISO weeks of logged volume, oldest first (current week last).
    private var weeklyVolumes: [(weekStart: Date, volume: Double)] {
        let cal = Calendar.current
        // §6 — locale-independent Monday: `Calendar.current`'s own
        // `dateInterval(of: .weekOfYear, for:)` starts the week on whatever the
        // device region calls the first day (Sunday for en_US), which shifted
        // this whole chart by a day on Sundays.
        let thisMonday = TrainingCalendar.mondayOfWeek(containing: Date())
        return (0 ..< 8).reversed().compactMap { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisMonday),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)
            else {
                return nil
            }
            let vol = allHistory
                .filter { $0.date >= start && $0.date < end }
                .reduce(0.0) { $0 + $1.totalVolume }
            return (start, vol)
        }
    }

    /// New running-max e1RMs set in the trailing 30 days, across all lifts.
    private var prCount30d: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var count = 0
        for exercise in exercises {
            let rows = (exercise.history ?? []).sorted { $0.date < $1.date }
            var runningMax = 0.0
            for row in rows {
                guard let e1RM = row.estimated1RM else {
                    continue
                }
                if e1RM > runningMax {
                    runningMax = e1RM
                    if row.date >= cutoff {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    /// Consecutive training weeks (≥1 completed workout). The current week
    /// counts when trained but never BREAKS the run while still in progress.
    private var weekStreak: Int {
        let cal = Calendar.current
        // §6 — locale-independent Monday (see weeklyVolumes above).
        let thisMonday = TrainingCalendar.mondayOfWeek(containing: Date())
        let completedDates = workoutPlans.filter { $0.status == .completed }.map(\.date)
        func trained(weekStarting cursor: Date) -> Bool {
            guard let end = cal.date(byAdding: .weekOfYear, value: 1, to: cursor) else {
                return false
            }
            return completedDates.contains { $0 >= cursor && $0 < end }
        }
        var streak = trained(weekStarting: thisMonday) ? 1 : 0
        var cursor = thisMonday
        for _ in 0 ..< 200 {
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else {
                break
            }
            cursor = prev
            guard trained(weekStarting: cursor) else {
                break
            }
            streak += 1
        }
        return streak
    }

    private var thisWeekHero: some View {
        let weeks = weeklyVolumes
        let current = weeks.last?.volume ?? 0
        let previous = weeks.dropLast().last?.volume ?? 0
        let delta = previous > 0 ? (current - previous) / previous : nil

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS WEEK")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text(formatVolume(current))
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .monospacedDigit()
                }
                Spacer()
                if let delta {
                    HStack(spacing: 2) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(abs(Int((delta * 100).rounded())))% vs last week")
                            .font(.tempoCaption1)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(delta >= 0 ? Color.tempoRecoveryGreen : Color.tempoAmber)
                }
            }

            if weeks.contains(where: { $0.volume > 0 }) {
                Chart(weeks, id: \.weekStart) { week in
                    AreaMark(
                        x: .value("Week", week.weekStart),
                        y: .value("Volume", week.volume)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.tempoAccent.opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                    LineMark(
                        x: .value("Week", week.weekStart),
                        y: .value("Volume", week.volume)
                    )
                    .foregroundStyle(Color.tempoAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 56)
            }

            HStack(spacing: TempoSpacing.lg) {
                Label("\(weekStreak)-week streak", systemImage: "flame.fill")
                    .foregroundStyle(weekStreak > 0 ? Color.tempoAmber : Color.tempoTextTertiary)
                Label("\(prCount30d) PRs this month", systemImage: "star.fill")
                    .foregroundStyle(prCount30d > 0 ? Color.tempoAccent : Color.tempoTextTertiary)
                Spacer()
            }
            .font(.tempoCaption1)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private var allTimeStats: some View {
        let totalWorkouts = workoutPlans.count(where: { $0.status == .completed })
        let totalVolume = allHistory.reduce(0.0) { $0 + $1.totalVolume }
        let totalSets = workoutPlans
            .filter { $0.status == .completed }
            .reduce(0) { $0 + $1.completedSets }

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("ALL-TIME")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: TempoSpacing.sm),
                GridItem(.flexible(), spacing: TempoSpacing.sm),
                GridItem(.flexible(), spacing: TempoSpacing.sm),
            ], spacing: TempoSpacing.sm) {
                overviewStatCell(label: "Workouts", value: "\(totalWorkouts)")
                overviewStatCell(label: "Volume", value: formatVolume(totalVolume))
                overviewStatCell(label: "Sets", value: "\(totalSets)")
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func overviewStatCell(label: String, value: String) -> some View {
        VStack(spacing: TempoSpacing.xxs) {
            Text(value)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    /// Per MODULE_TRAINING.md Section 11.4 — Workout frequency bar chart.
    /// §11.8 — 8 weeks with the average as a dashed rule, current week accented.
    private var workoutFrequencyCard: some View {
        let recentWeeks = weeklyWorkoutCounts(weeks: 8)
        let average = recentWeeks.isEmpty
            ? 0
            : Double(recentWeeks.reduce(0) { $0 + $1.count }) / Double(recentWeeks.count)

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("WORKOUT FREQUENCY")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if average > 0 {
                    Text(String(format: "avg %.1f/wk", average))
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            if recentWeeks.isEmpty {
                Text("No workouts yet")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            } else {
                Chart {
                    ForEach(Array(recentWeeks.enumerated()), id: \.element.weekLabel) { idx, item in
                        BarMark(
                            x: .value("Week", item.weekLabel),
                            y: .value("Count", item.count)
                        )
                        .foregroundStyle(
                            idx == recentWeeks.count - 1
                                ? Color.tempoAccent
                                : Color.tempoSignal.opacity(0.7)
                        )
                        .cornerRadius(TempoRadius.xs)
                    }
                    if average > 0 {
                        RuleMark(y: .value("Average", average))
                            .foregroundStyle(Color.tempoTextTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                            .foregroundStyle(Color.tempoTextTertiary.opacity(0.2))
                        AxisValueLabel()
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    /// Per MODULE_TRAINING.md Section 11.4 — Body part split donut chart
    private var bodyPartSplitCard: some View {
        let distribution = muscleGroupDistribution

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("MUSCLE GROUP DISTRIBUTION")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            if distribution.isEmpty {
                Text("No data yet")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            } else {
                ForEach(distribution, id: \.group) { item in
                    HStack(spacing: TempoSpacing.sm) {
                        Text(item.group.displayName)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .frame(width: 80, alignment: .leading)

                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous)
                                .fill(Color.tempoSignal)
                                .frame(width: max(4, geo.size.width * item.percentage))
                        }
                        .frame(height: 12)

                        Text("\(Int(item.percentage * 100))%")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Exercises Tab

    // Per MODULE_TRAINING.md Section 11.2

    private var exercisesTab: some View {
        let exercisesWithHistory = exercises.filter { ($0.history?.isEmpty ?? true) == false }

        return LazyVStack(spacing: TempoSpacing.sm) {
            if exercisesWithHistory.isEmpty {
                VStack(spacing: TempoSpacing.md) {
                    Spacer().frame(height: 80)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("Complete workouts to see progress")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(exercisesWithHistory, id: \.id) { exercise in
                    NavigationLink {
                        ExerciseDetailView(exercise: exercise)
                    } label: {
                        exerciseProgressRow(exercise)
                    }
                }
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
    }

    private func exerciseProgressRow(_ exercise: Exercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(exercise.name.uppercased())
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                if let e1rm = exercise.currentEstimated1RM {
                    Text("e1RM: \(String(format: "%.1f", e1rm)) kg")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }

            Spacer()

            Text(exercise.muscleGroup.displayName)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.horizontal, TempoSpacing.xs)
                .padding(.vertical, 2)
                .background(Color.tempoSurfaceElevated)
                .clipShape(Capsule())

            Image(systemName: "chevron.right")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Muscle Groups Tab

    // Per MODULE_TRAINING.md Section 11.3

    private var muscleGroupsTab: some View {
        let distribution = muscleGroupDistribution

        return VStack(spacing: TempoSpacing.xl) {
            // Weekly volume by muscle group
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                Text("WEEKLY VOLUME BY MUSCLE GROUP")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)

                if distribution.isEmpty {
                    Text("No data yet")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                } else {
                    ForEach(distribution, id: \.group) { item in
                        HStack(spacing: TempoSpacing.sm) {
                            Text(item.group.displayName)
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .frame(width: 80, alignment: .leading)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous)
                                    .fill(Color.tempoSignal)
                                    .frame(width: max(4, geo.size.width * item.percentage))
                            }
                            .frame(height: 16)

                            Text(formatVolume(item.volume))
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

            // Balance analysis
            // Per MODULE_TRAINING.md Section 11.3 — Push/Pull ratio
            balanceAnalysis
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
    }

    private var balanceAnalysis: some View {
        let dist = muscleGroupDistribution
        let pushVolume = dist.filter { [.chest, .shoulders, .triceps].contains($0.group) }
            .reduce(0.0) { $0 + $1.volume }
        let pullVolume = dist.filter { [.back, .biceps].contains($0.group) }
            .reduce(0.0) { $0 + $1.volume }
        let ratio = pullVolume > 0 ? pushVolume / pullVolume : 0

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("BALANCE ANALYSIS")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            HStack(spacing: TempoSpacing.sm) {
                let isBalanced = ratio >= 0.8 && ratio <= 1.3
                Image(systemName: isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.tempoBody)
                    .foregroundStyle(isBalanced ? Color.tempoRecoveryGreen : Color.tempoRecoveryYellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Push/Pull Ratio")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(ratio > 0 ? String(format: "%.1f:1 (ideal: 1:1)", ratio) : "Not enough data")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    // MARK: - Activity Tab (non-gym: football / sprint / conditioning)

    private var activityTab: some View {
        VStack(spacing: TempoSpacing.lg) {
            if activitySessions.isEmpty {
                EmptyStateView(
                    icon: "figure.run",
                    title: "No Activity Yet",
                    message: "Log a football, run, or conditioning session to track it here."
                )
                .padding(.top, TempoSpacing.xxxl)
            } else {
                // All-time totals
                HStack(spacing: 0) {
                    activityTotal("\(activitySessions.count)", "Sessions")
                    activityTotal("\(Int(totalActiveMinutes))m", "Active")
                    activityTotal(String(format: "%.0f", totalActivityStrain), "Total Strain")
                }
                .padding(TempoSpacing.cardPadding)
                .frame(maxWidth: .infinity)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                // Recent sessions
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text("RECENT SESSIONS")
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextTertiary)

                    ForEach(activitySessions.prefix(20), id: \.id) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activityTypeLabel(session))
                                    .font(.tempoBody)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.tempoTextPrimary)
                                Text(session.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                    .font(.tempoCaption2)
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let strain = session.strain {
                                    Text(String(format: "%.1f strain", strain))
                                        .font(.tempoCaption1)
                                        .foregroundStyle(Color.tempoTextSecondary)
                                }
                                if let mins = session.durationMinutes {
                                    Text("\(Int(mins)) min")
                                        .font(.tempoCaption2)
                                        .foregroundStyle(Color.tempoTextTertiary)
                                }
                            }
                        }
                        .padding(.vertical, TempoSpacing.xs)
                    }
                }
                .padding(TempoSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.xxxl)
    }

    private var totalActiveMinutes: Double {
        activitySessions.compactMap(\.durationMinutes).reduce(0, +)
    }

    private var totalActivityStrain: Double {
        activitySessions.compactMap(\.strain).reduce(0, +)
    }

    private func activityTotal(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func activityTypeLabel(_ session: ActivitySession) -> String {
        WorkoutType(rawValue: session.workoutType)?.displayName ?? session.workoutType.capitalized
    }

    // MARK: - Helpers

    private struct WeekCount {
        let weekLabel: String
        let count: Int
    }

    private func weeklyWorkoutCounts(weeks: Int) -> [WeekCount] {
        let cal = Calendar.current
        // §6 — anchor to Monday (not just "today"), consistent with
        // weeklyVolumes/weekStreak above — a rolling today-anchored window
        // otherwise split a Mon-Sun training week across two bars depending on
        // which weekday the chart happened to render on.
        let today = TrainingCalendar.mondayOfWeek(containing: Date())
        return (0 ..< weeks).reversed().map { weekOffset in
            let weekStart = cal.date(byAdding: .weekOfYear, value: -weekOffset, to: today)!
            let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
            let count = workoutPlans.count(where: {
                $0.status == .completed && $0.date >= weekStart && $0.date < weekEnd
            })
            return WeekCount(weekLabel: "W\(weeks - weekOffset)", count: count)
        }
    }

    private struct MuscleDistribution {
        let group: MuscleGroup
        let volume: Double
        let percentage: Double
    }

    private var muscleGroupDistribution: [MuscleDistribution] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recentHistory = allHistory.filter { $0.date > thirtyDaysAgo }

        var volumeByGroup: [MuscleGroup: Double] = [:]
        for entry in recentHistory {
            if let group = entry.exercise?.muscleGroup {
                volumeByGroup[group, default: 0] += entry.totalVolume
            }
        }

        let total = volumeByGroup.values.reduce(0, +)
        guard total > 0 else {
            return []
        }

        return volumeByGroup
            .map { MuscleDistribution(group: $0.key, volume: $0.value, percentage: $0.value / total) }
            .sorted { $0.volume > $1.volume }
    }

    /// Stored kg → the user's display unit (a lbs lifter reads lbs totals).
    private func formatVolume(_ volumeKg: Double) -> String {
        let value = WeightUnit.kg.convert(volumeKg, to: weightUnit)
        if value >= 1000 {
            return String(format: "%.1fk %@", value / 1000, weightUnit.abbreviation)
        }
        return "\(Int(value)) \(weightUnit.abbreviation)"
    }
}
