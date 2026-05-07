//
// WeekPlanView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - WeekPlanView

// Per MODULE_TRAINING.md Section 9 — 7-day training plan grid.
// Per WIREFRAMES.md Section 3 — Week plan layout.

struct WeekPlanView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @State
    private var expandedPlanID: UUID?

    private let dayAbbreviations = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private let calendar = Calendar.current

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Week header
                weekHeader

                // Deload week indicator
                if viewModel.isDeloadWeek {
                    deloadBanner
                }

                // 7-day grid
                // Per MODULE_TRAINING.md Section 9.2
                dayGrid

                // Daily detail cards
                dailyCards
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("This Week")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadWeekPlan(modelContext: modelContext)
        }
    }

    // MARK: - Week Header

    private var weekHeader: some View {
        let plans = viewModel.weekPlans
        let dateText: String = {
            guard let first = plans.first?.date, let last = plans.last?.date else {
                return ""
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: first)) – \(formatter.string(from: last)), \(calendar.component(.year, from: first))"
        }()

        return Text(dateText)
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoTextSecondary)
            .padding(.top, TempoSpacing.md)
    }

    // MARK: - Deload Banner

    private var deloadBanner: some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.tempoRecoveryYellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("DELOAD WEEK")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoRecoveryYellow)

                Text("Weights reduced 40% — same reps, lighter load. Your body rebuilds stronger.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoRecoveryYellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                .stroke(Color.tempoRecoveryYellow.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 7-Day Grid

    // Per MODULE_TRAINING.md Section 9.2

    private var dayGrid: some View {
        HStack(spacing: TempoSpacing.xxs) {
            ForEach(Array(viewModel.weekPlans.enumerated()), id: \.element.id) { index, plan in
                dayCell(plan: plan, dayLabel: dayAbbreviations[safe: index] ?? "")
            }
        }
    }

    private func dayCell(plan: WorkoutPlan, dayLabel: String) -> some View {
        let isToday = calendar.isDateInToday(plan.date)
        let isCompleted = plan.status == .completed

        return VStack(spacing: TempoSpacing.xxs) {
            // Day label
            Text(dayLabel)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            // Recovery dot
            Circle()
                .fill(recoveryDotColor(plan: plan))
                .frame(width: 8, height: 8)

            // Workout type abbreviation
            Text(workoutAbbreviation(plan.type))
                .font(.tempoCaption2)
                .fontWeight(.medium)
                .foregroundStyle(workoutTypeColor(plan: plan))

            // Status indicator
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.tempoRecoveryGreen)
            } else if plan.type == .football {
                Image(systemName: "sportscourt")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                Color.clear.frame(width: 10, height: 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.sm)
        .background(
            isToday
                ? Color.tempoSurfaceCard
                : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                .stroke(isToday ? Color.tempoSignal : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
    }

    // MARK: - Daily Detail Cards

    // Per MODULE_TRAINING.md Section 9.3

    private var dailyCards: some View {
        VStack(spacing: TempoSpacing.sm) {
            ForEach(viewModel.weekPlans, id: \.id) { plan in
                dailyCard(plan: plan)
            }
        }
    }

    private func dailyCard(plan: WorkoutPlan) -> some View {
        let isToday = calendar.isDateInToday(plan.date)
        let isCompleted = plan.status == .completed
        let dayName = dayName(for: plan.date)
        let isExpanded = expandedPlanID == plan.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedPlanID = isExpanded ? nil : plan.id
                }
            } label: {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    // Day label
                    HStack(spacing: TempoSpacing.sm) {
                        if isToday {
                            Text("TODAY")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoSignal)
                        } else {
                            Text(dayName)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }

                    // Workout info
                    HStack {
                        // Icon
                        Image(systemName: workoutIcon(plan.type))
                            .font(.tempoBody)
                            .foregroundStyle(workoutTypeColor(plan: plan))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: TempoSpacing.xs) {
                                Text(plan.type.displayName.uppercased())
                                    .font(.tempoHeadline)
                                    .foregroundStyle(Color.tempoTextPrimary)

                                if isCompleted {
                                    Text("— Completed")
                                        .font(.tempoCaption1)
                                        .foregroundStyle(Color.tempoRecoveryGreen)
                                }
                            }

                            // Meta line
                            if plan.type.isGymWorkout {
                                Text(
                                    "~\(plan.durationMinutes ?? estimatedDuration(plan: plan)) min · \(plan.orderedExercises.count) exercises"
                                )
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                            } else if plan.type == .football {
                                Text("Match day")
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            } else if plan.type == .rest {
                                Text("Recovery day")
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            } else if plan.type == .mobility {
                                Text("~25 min · Active recovery")
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            }
                        }

                        Spacer()

                        if isCompleted, let duration = plan.actualDurationMinutes {
                            Text("\(duration) min")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .padding(TempoSpacing.cardPadding)
            }
            .buttonStyle(.plain)

            // Expanded exercise list
            if isExpanded, plan.type.isGymWorkout {
                Divider()
                    .padding(.horizontal, TempoSpacing.cardPadding)

                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    ForEach(Array(plan.orderedExercises.enumerated()), id: \.element.id) { index, plannedEx in
                        HStack(spacing: TempoSpacing.sm) {
                            Text("\(index + 1)")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                                .frame(width: 16, alignment: .trailing)

                            Text(plannedEx.exercise?.name ?? "Exercise")
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .lineLimit(1)

                            Spacer()

                            if let sets = plannedEx.sets {
                                Text("\(sets.count) sets")
                                    .font(.tempoCaption2)
                                    .foregroundStyle(Color.tempoTextSecondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, TempoSpacing.cardPadding)
                .padding(.vertical, TempoSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Helpers

    private func workoutAbbreviation(_ type: WorkoutType) -> String {
        switch type {
        case .push: "PSH"
        case .pull: "PUL"
        case .legs: "LEG"
        case .upper: "UPR"
        case .lower: "LWR"
        case .fullBody: "FUL"
        case .football: "FTB"
        case .run: "RUN"
        case .mobility: "MOB"
        case .rest: "RST"
        case .sprint: "SPR"
        case .conditioning: "CON"
        }
    }

    private func workoutIcon(_ type: WorkoutType) -> String {
        switch type {
        case .push,
             .pull,
             .legs,
             .upper,
             .lower,
             .fullBody:
            "figure.strengthtraining.traditional"
        case .football: "sportscourt"
        case .run,
             .sprint: "figure.run"
        case .conditioning: "flame"
        case .mobility: "figure.flexibility"
        case .rest: "bed.double"
        }
    }

    private func workoutTypeColor(plan: WorkoutPlan) -> Color {
        if plan.status == .completed {
            return Color.tempoRecoveryGreen
        }
        switch plan.type {
        case .football: return Color.tempoRecoveryYellow
        case .rest: return Color.tempoTextTertiary
        case .mobility: return Color.tempoTextSecondary
        default: return Color.tempoTextPrimary
        }
    }

    private func recoveryDotColor(plan: WorkoutPlan) -> Color {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return Color.tempoRecoveryGreen
        }
        if adj >= 0.6 {
            return Color.tempoRecoveryYellow
        }
        return Color.tempoRecoveryRed
    }

    private func dayName(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func estimatedDuration(plan: WorkoutPlan) -> Int {
        let exercises = plan.orderedExercises
        guard !exercises.isEmpty else {
            return 20
        }

        var totalMinutes = 5.0 // Warmup period

        for (index, plannedEx) in exercises.enumerated() {
            let sets = plannedEx.orderedSets
            let isCompound = plannedEx.exercise?.isCompound ?? false

            for set in sets {
                if set.isWarmup {
                    totalMinutes += 1.0
                } else if isCompound {
                    totalMinutes += 2.5
                } else {
                    totalMinutes += 1.5
                }
            }

            if index < exercises.count - 1 {
                totalMinutes += 1.0 // Between-exercise transition
            }
        }

        totalMinutes += 3.0 // Cooldown

        return max(20, Int(totalMinutes.rounded()))
    }
}

// MARK: - Safe Array Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
