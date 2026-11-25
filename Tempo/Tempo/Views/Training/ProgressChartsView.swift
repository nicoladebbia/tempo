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

// The one Progress page in Train. Five tabs: Overview (the week, load, totals,
// frequency, muscle split, other training), Lifts (the Strength Lab and every
// lift with history), Records (personal records), Body (the muscle map, volume
// by muscle and push/pull balance) and History (every logged workout, with CSV
// import and export). Per MODULE_TRAINING.md Section 11 and WIREFRAMES.md Screen 21.

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
    @Query(filter: #Predicate<Goal> { $0.isActive == true })
    private var activeGoals: [Goal]

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    @State
    private var selectedTab: ProgressTab = .overview

    enum ProgressTab: String, CaseIterable {
        case overview = "Overview"
        case lifts = "Lifts"
        case records = "Records"
        case body = "Body"
        case history = "History"

        /// The label on the tab strip; the raw value stays the English identifier.
        var label: String {
            switch self {
            case .overview: String(localized: "Overview")
            case .lifts: String(localized: "Lifts")
            case .records: String(localized: "Records")
            case .body: String(localized: "Body")
            case .history: String(localized: "History")
            }
        }
    }

    private var hasAnyData: Bool {
        workoutPlans.contains(where: { $0.status == .completed })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Per MODULE_TRAINING.md Section 11.1 — segmented control at top.
            // Always shown: History is where workouts are imported from
            // another app, so it must be reachable before the first workout.
            TrainPlanTabs(
                items: ProgressTab.allCases.map { (tag: $0, label: $0.label) },
                selection: $selectedTab
            )
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s2)

            if selectedTab == .history {
                // Its own scrolling list, import overlay and toolbar buttons.
                WorkoutHistoryView()
            } else {
                TrainPlanPage {
                    if hasAnyData {
                        tabContent
                    } else {
                        noProgressCard
                    }
                }
                .id(selectedTab)
            }
        }
        .tidePage()
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .firstTip(
            "train.progress",
            "Switch tabs for your lifts, records, body and history, and tap a score or number to see how it is worked out.",
            systemImage: "chart.line.uptrend.xyaxis"
        )
        // NOTE: there is deliberately NO orphan-purge on appearance. A prior
        // purgeOrphanedHistory() ran here and DELETED valid ExerciseHistory on
        // every Progress open whenever the matching WorkoutPlan wasn't marked
        // .completed — a data-loss bug. ExerciseHistory is the permanent
        // training record and is independent of the ephemeral daily
        // WorkoutPlan (no schema relationship); its validity is never derived
        // from plan status. Orphan cleanup happens only at explicit user
        // deletion in WorkoutHistoryView.deleteWorkout(), keyed by workoutPlanID.
    }

    /// The tab's content (History has its own list and is not in here).
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .lifts:
            liftsTab
        case .records:
            ProgressRecordsView()
        case .body:
            bodyTab
        case .history:
            EmptyView()
        }
    }

    /// Before the first workout every tab but History is empty: say so, and
    /// where an earlier history can be brought in.
    private var noProgressCard: some View {
        VStack(spacing: Tide.s3) {
            TrainEmptyCard(
                systemImage: "chart.line.uptrend.xyaxis",
                title: String(localized: "No progress yet"),
                message: String(localized: "Complete your first workout to start tracking progress.")
            )
            Button {
                withAnimation(Tide.snap) {
                    selectedTab = .history
                }
            } label: {
                Label("Import history from another app", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.trainPlanSecondary)
        }
        .padding(.top, Tide.s4)
    }

    // MARK: - Overview Tab

    // Per MODULE_TRAINING.md Section 11.4

    private var overviewTab: some View {
        VStack(spacing: Tide.s4) {
            // The lift or run target, when there is one.
            if activeGoals.hasActive(of: [.liftE1RM, .runTime]) {
                GoalProgressChip(kinds: [.liftE1RM, .runTime])
            }

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

            // Football, sprints and conditioning (only once there are any).
            if !activitySessions.isEmpty {
                otherTrainingCards
            }
        }
    }

    // MARK: - Lifts Tab

    /// The Strength Lab on top, then every lift that has history.
    private var liftsTab: some View {
        VStack(spacing: Tide.s4) {
            // §11.2 — the interactive Strength Lab (scrubbable e1RM curve, PR
            // stars, compare lift, volume bars).
            StrengthProgressLabView()
            exercisesList
        }
    }

    // MARK: - Body Tab

    /// The muscle map, then volume by muscle and the push/pull balance.
    private var bodyTab: some View {
        VStack(spacing: Tide.s4) {
            MuscleHeatmapView()
            muscleVolumeCard
            balanceAnalysis
        }
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
    /// A lift's first session is its baseline, not a record (same rule as
    /// the PR toast), so a new lift doesn't inflate the count.
    private var prCount30d: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        var count = 0
        for exercise in exercises {
            let rows = (exercise.history ?? []).sorted { $0.date < $1.date }
            var runningMax: Double?
            for row in rows {
                guard let e1RM = row.estimated1RM, e1RM > 0 else {
                    continue
                }
                guard let best = runningMax else {
                    runningMax = e1RM
                    continue
                }
                if e1RM > best + TrainingEngine.personalRecordEpsilon {
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

        return TrainPlanCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    heroFigure(current)
                    Spacer(minLength: Tide.s2)
                    if let delta {
                        TrainPlanDelta(fraction: delta, suffix: String(localized: "vs last week"))
                    }
                }
                VStack(alignment: .leading, spacing: Tide.s2) {
                    heroFigure(current)
                    if let delta {
                        TrainPlanDelta(fraction: delta, suffix: String(localized: "vs last week"))
                    }
                }
            }

            if weeks.contains(where: { $0.volume > 0 }) {
                TrainPlanSpark(values: weeks.map(\.volume))
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) {
                    streakTags
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Tide.s2) {
                    streakTags
                }
            }
        }
    }

    private func heroFigure(_ volume: Double) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text("This week").tideLabel(Tide.text3)
                .lineLimit(1)
            Text(formatVolume(volume))
                .trainNumeral(Tide.numeralL, relativeTo: .largeTitle)
                .foregroundStyle(Tide.text)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private var streakTags: some View {
        TrainTag(
            text: String(localized: "\(weekStreak)-week streak"),
            systemImage: "flame.fill",
            color: weekStreak > 0 ? TideTrain.caution : Tide.text3
        )
        TrainTag(
            text: String(localized: "\(prCount30d) PRs this month"),
            systemImage: "star.fill",
            color: prCount30d > 0 ? Color.accentColor : Tide.text3
        )
    }

    private var allTimeStats: some View {
        let totalWorkouts = workoutPlans.count(where: { $0.status == .completed })
        let totalVolume = allHistory.reduce(0.0) { $0 + $1.totalVolume }
        let totalSets = workoutPlans
            .filter { $0.status == .completed }
            .reduce(0) { $0 + $1.completedSets }

        return TrainPlanCard(label: String(localized: "All-time")) {
            TrainStatGrid {
                TrainStat(value: "\(totalWorkouts)", label: TrainCount.noun(totalWorkouts, "Workout"))
                TrainStat(
                    value: WeightFormat.compactVolume(kg: totalVolume, unit: weightUnit),
                    label: String(localized: "Volume (\(weightUnit.abbreviation))")
                )
                TrainStat(value: "\(totalSets)", label: TrainCount.noun(totalSets, "Set"))
            }
        }
    }

    /// Per MODULE_TRAINING.md Section 11.4 — Workout frequency bar chart.
    /// §11.8 — 8 weeks with the average as a dashed rule, current week accented.
    private var workoutFrequencyCard: some View {
        let recentWeeks = weeklyWorkoutCounts(weeks: 8)
        let average = recentWeeks.isEmpty
            ? 0
            : Double(recentWeeks.reduce(0) { $0 + $1.count }) / Double(recentWeeks.count)

        return TrainPlanCard(
            label: String(localized: "Workout frequency"),
            trailing: average > 0 ? String(localized: "avg \(average.tempoDecimal(1))/wk") : nil
        ) {
            if recentWeeks.isEmpty {
                emptyLine(String(localized: "No workouts yet"), height: TideTrain.barsHeight)
            } else {
                TrainPlanBarChart(
                    bars: recentWeeks.map {
                        TrainPlanBarChart.Bar(id: $0.weekLabel, label: $0.weekLabel, value: Double($0.count))
                    },
                    average: average
                )
            }
        }
    }

    /// Per MODULE_TRAINING.md Section 11.4 — Body part split donut chart
    private var bodyPartSplitCard: some View {
        let distribution = muscleGroupDistribution

        return TrainPlanCard(label: String(localized: "Muscle group distribution"), trailing: String(localized: "30 days")) {
            if distribution.isEmpty {
                emptyLine(String(localized: "No data yet"), height: TideTrain.barsHeight)
            } else {
                ForEach(distribution, id: \.group) { item in
                    TrainPlanMeterRow(
                        label: item.group.displayName,
                        value: "\(Int(item.percentage * 100))%",
                        fraction: item.percentage
                    )
                }
            }
        }
    }

    private func emptyLine(_ text: String, height: CGFloat) -> some View {
        Text(text)
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
            .frame(maxWidth: .infinity, minHeight: height)
    }

    // MARK: - Lifts list

    // Per MODULE_TRAINING.md Section 11.2

    /// Every lift with history, each opening its exercise page. (When there
    /// are none, the Strength Lab above already says so.)
    @ViewBuilder
    private var exercisesList: some View {
        let exercisesWithHistory = exercises.filter { ($0.history?.isEmpty ?? true) == false }
        if !exercisesWithHistory.isEmpty {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: String(localized: "All lifts"), trailing: TrainCount.text(exercisesWithHistory.count, "lift"))
                    .padding(.top, Tide.s2)
                LazyVStack(spacing: Tide.s2) {
                    ForEach(exercisesWithHistory, id: \.id) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            exerciseProgressRow(exercise)
                        }
                        .buttonStyle(.trainCard)
                    }
                }
            }
        }
    }

    private func exerciseProgressRow(_ exercise: Exercise) -> some View {
        let info = VStack(alignment: .leading, spacing: Tide.hair) {
            Text(exercise.name)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            if let e1rm = exercise.currentEstimated1RM, e1rm > 0 {
                Text("e1RM: \(WeightFormat.text(kg: e1rm, unit: weightUnit))")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
        }
        let chevron = Image(systemName: "chevron.right")
            .font(Tide.label)
            .foregroundStyle(Tide.text3)
            .accessibilityHidden(true)
        // The muscle tag goes under the name once the row runs out of width.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                info
                Spacer(minLength: Tide.s2)
                TrainTag(text: exercise.muscleGroup.displayName)
                chevron
            }
            HStack(alignment: .top, spacing: Tide.s3) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    info
                    TrainTag(text: exercise.muscleGroup.displayName)
                }
                Spacer(minLength: Tide.s2)
                chevron
            }
        }
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
    }

    // MARK: - Muscle volume

    // Per MODULE_TRAINING.md Section 11.3

    /// Volume per muscle group over the last 30 days (the distribution's own window).
    private var muscleVolumeCard: some View {
        let distribution = muscleGroupDistribution
        return TrainPlanCard(label: String(localized: "Volume by muscle group"), trailing: String(localized: "30 days")) {
            if distribution.isEmpty {
                emptyLine(String(localized: "No data yet"), height: TideTrain.barsHeight)
            } else {
                ForEach(distribution, id: \.group) { item in
                    TrainPlanMeterRow(
                        label: item.group.displayName,
                        value: formatVolume(item.volume),
                        fraction: item.percentage
                    )
                }
            }
        }
    }

    private var balanceAnalysis: some View {
        let dist = muscleGroupDistribution
        let pushVolume = dist.filter { [.chest, .shoulders, .triceps].contains($0.group) }
            .reduce(0.0) { $0 + $1.volume }
        let pullVolume = dist.filter { [.back, .biceps].contains($0.group) }
            .reduce(0.0) { $0 + $1.volume }
        let ratio = pullVolume > 0 ? pushVolume / pullVolume : 0
        let isBalanced = ratio >= 0.8 && ratio <= 1.3

        return TrainPlanCard(label: String(localized: "Balance analysis")) {
            HStack(spacing: Tide.s3) {
                TideIconTile(
                    systemName: isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: isBalanced ? TideTrain.positive : TideTrain.caution
                )

                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("Push/Pull Ratio")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)

                    Text(ratio > 0 ? String(localized: "\(ratio.tempoDecimal(1)):1 (ideal: 1:1)") : String(localized: "Not enough data"))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .explains(TrainExplainers.pushPull)
        }
    }

    // MARK: - Other training (non-gym: football / sprint / conditioning)

    /// The all-time totals and the recent sessions of everything that is not a
    /// gym workout. Shown on Overview only when there is at least one.
    private var otherTrainingCards: some View {
        VStack(spacing: Tide.s4) {
            TrainPlanCard(label: String(localized: "Football, runs and conditioning")) {
                TrainStatGrid {
                    TrainStat(value: "\(activitySessions.count)", label: TrainCount.noun(activitySessions.count, "Session"))
                    TrainStat(value: String(localized: "\(Int(totalActiveMinutes))m"), label: String(localized: "Active"))
                    TrainStat(
                        value: totalActivityStrain.tempoDecimal(0), label: String(localized: "Total strain"),
                        explainer: TrainExplainers.strain
                    )
                }
            }

            TrainPlanCard(label: String(localized: "Recent sessions")) {
                let recent = Array(activitySessions.prefix(20))
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, session in
                    if index > 0 {
                        TrainPlanDivider()
                    }
                    activityRow(session)
                }
            }
        }
    }

    /// One logged activity: what and when on the left, strain and minutes on
    /// the right, stacked once the row runs out of width.
    private func activityRow(_ session: ActivitySession) -> some View {
        let info = VStack(alignment: .leading, spacing: Tide.hair) {
            Text(activityTypeLabel(session))
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
        let figures = VStack(alignment: .trailing, spacing: Tide.hair) {
            if let strain = session.strain {
                Text(String(localized: "\(strain.tempoDecimal(1)) strain"))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
            if let mins = session.durationMinutes {
                Text("\(Int(mins)) min")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                info
                Spacer(minLength: Tide.s2)
                figures
            }
            VStack(alignment: .leading, spacing: Tide.s1) {
                info
                figures
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var totalActiveMinutes: Double {
        activitySessions.compactMap(\.durationMinutes).reduce(0, +)
    }

    private var totalActivityStrain: Double {
        activitySessions.compactMap(\.strain).reduce(0, +)
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
            return WeekCount(weekLabel: String(localized: "W\(weeks - weekOffset)"), count: count)
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
        WeightFormat.volumeText(kg: volumeKg, unit: weightUnit)
    }
}
