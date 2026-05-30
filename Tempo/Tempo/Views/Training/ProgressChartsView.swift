//
// ProgressChartsView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Charts
import OSLog
import SwiftData
import SwiftUI

// MARK: - Progress Charts View

// Per MODULE_TRAINING.md Section 11 — Three tabs: Per Exercise, Muscle Groups, Overview.
// Per WIREFRAMES.md Screen 21 — Progress chart per exercise.

struct ProgressChartsView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query(sort: \ExerciseHistory.date, order: .reverse)
    private var allHistory: [ExerciseHistory]
    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]
    @Query(sort: \WorkoutPlan.date, order: .reverse)
    private var workoutPlans: [WorkoutPlan]

    @State
    private var selectedTab: ProgressTab = .overview

    enum ProgressTab: String, CaseIterable {
        case overview = "Overview"
        case exercises = "Exercises"
        case muscles = "Muscles"
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
                    case .overview:
                        overviewTab
                    case .exercises:
                        exercisesTab
                    case .muscles:
                        muscleGroupsTab
                    }
                }
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        // NOTE: purgeOrphanedHistory() was removed from here — it was DELETING
        // valid ExerciseHistory on every Progress open whenever the matching
        // WorkoutPlan wasn't marked .completed (data-loss bug). History is the
        // permanent record and is independent of the ephemeral WorkoutPlan;
        // orphan cleanup belongs at explicit user deletion (WorkoutHistoryView),
        // not on view appearance. The function body is left dead pending its
        // removal once the write-path + plan-churn fixes land.
    }

    // ExerciseHistory has no relationship back to WorkoutPlan, so historically a
    // user could delete a workout from History and leave behind ExerciseHistory
    // rows that still showed in Progress. WorkoutHistoryView.deleteWorkout() now
    // cascades correctly for new deletions, but pre-existing orphans linger.
    // Purge them on Progress appearance: any history row whose (day, exercise.id)
    // doesn't correspond to a completed WorkoutPlan is dead weight.
    private func purgeOrphanedHistory() {
        let historySnapshot = Array(allHistory)
        guard !historySnapshot.isEmpty else {
            Logger.training.info("[purge] no history rows, nothing to do")
            return
        }
        let cal = Calendar.current
        var validKeys = Set<String>()
        for plan in workoutPlans where plan.status == .completed {
            let day = cal.startOfDay(for: plan.finishedAt ?? plan.date)
            for plannedEx in plan.orderedExercises {
                if let exID = plannedEx.exercise?.id {
                    validKeys.insert("\(day.timeIntervalSince1970)|\(exID.uuidString)")
                }
            }
        }
        Logger.training.info("[purge] historySnapshot.count=\(historySnapshot.count) validKeys.count=\(validKeys.count) completedPlans=\(workoutPlans.filter { $0.status == .completed }.count)")

        var toDelete: [ExerciseHistory] = []
        for entry in historySnapshot {
            let day = cal.startOfDay(for: entry.date)
            let key = "\(day.timeIntervalSince1970)|\(entry.exercise?.id.uuidString ?? "nil")"
            if !validKeys.contains(key) {
                toDelete.append(entry)
                Logger.training.debug("[purge] orphan vol=\(entry.totalVolume) ex=\(entry.exercise?.name ?? "nil") day=\(day)")
            }
        }
        guard !toDelete.isEmpty else {
            Logger.training.info("[purge] no orphans found")
            return
        }
        for entry in toDelete {
            modelContext.delete(entry)
        }
        do {
            try modelContext.save()
            Logger.training.info("[purge] deleted \(toDelete.count) orphan ExerciseHistory rows")
        } catch {
            Logger.training.error("[purge] save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Overview Tab

    // Per MODULE_TRAINING.md Section 11.4

    private var overviewTab: some View {
        VStack(spacing: TempoSpacing.xl) {
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

    /// Per MODULE_TRAINING.md Section 11.4 — Workout frequency bar chart
    private var workoutFrequencyCard: some View {
        let last4Weeks = weeklyWorkoutCounts(weeks: 4)

        return VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("WORKOUT FREQUENCY")
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)

            if last4Weeks.isEmpty {
                Text("No workouts yet")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
            } else {
                Chart(last4Weeks, id: \.weekLabel) { item in
                    BarMark(
                        x: .value("Week", item.weekLabel),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(Color.tempoSignal)
                    .cornerRadius(TempoRadius.xs)
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

    // MARK: - Helpers

    private struct WeekCount {
        let weekLabel: String
        let count: Int
    }

    private func weeklyWorkoutCounts(weeks: Int) -> [WeekCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
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

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume)) kg"
    }
}
