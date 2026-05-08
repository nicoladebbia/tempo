//
// WorkoutHistoryView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Workout History View

// Shows completed workouts sorted by date descending.
// Tapping a card expands to show per-exercise detail (sets/reps/weight).

struct WorkoutHistoryView: View {
    @Query(
        filter: #Predicate<WorkoutPlan> { $0.statusRaw == "completed" },
        sort: \WorkoutPlan.date,
        order: .reverse
    )
    private var completedWorkouts: [WorkoutPlan]

    @State
    private var expandedWorkoutID: UUID?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if completedWorkouts.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No Workouts Yet",
                    message: "Complete your first workout to see your history here."
                )
                .frame(minHeight: 400)
            } else {
                LazyVStack(spacing: TempoSpacing.sm) {
                    ForEach(completedWorkouts, id: \.id) { workout in
                        workoutCard(workout)
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Workout Card

    private func workoutCard(_ workout: WorkoutPlan) -> some View {
        let isExpanded = expandedWorkoutID == workout.id

        return VStack(spacing: 0) {
            // Main card content
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedWorkoutID = isExpanded ? nil : workout.id
                }
                HapticManager.selection()
            } label: {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    // Row 1: Date + workout type
                    HStack {
                        Text(workout.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)

                        Spacer()

                        Text(workout.type.displayName.uppercased())
                            .font(.tempoCaption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.tempoSignal)
                            .padding(.horizontal, TempoSpacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.tempoSignal.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    // Row 2: Stats
                    HStack(spacing: TempoSpacing.md) {
                        // Duration
                        if let duration = workout.durationMinutes ?? workout.actualDurationMinutes {
                            HStack(spacing: TempoSpacing.xxs) {
                                Image(systemName: "timer")
                                    .font(.system(size: 11))
                                Text("\(duration) min")
                                    .font(.tempoCaption1)
                            }
                            .foregroundStyle(Color.tempoTextSecondary)
                        }

                        // Exercise count
                        let exerciseCount = workout.orderedExercises.count
                        if exerciseCount > 0 {
                            HStack(spacing: TempoSpacing.xxs) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 11))
                                Text("\(exerciseCount) exercises")
                                    .font(.tempoCaption1)
                            }
                            .foregroundStyle(Color.tempoTextSecondary)
                        }

                        // Total volume
                        let vol = workout.totalVolume
                        if vol > 0 {
                            HStack(spacing: TempoSpacing.xxs) {
                                Image(systemName: "scalemass")
                                    .font(.system(size: 11))
                                Text(formatVolume(vol))
                                    .font(.tempoCaption1)
                            }
                            .foregroundStyle(Color.tempoTextSecondary)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .padding(TempoSpacing.cardPadding)
            }
            .buttonStyle(.plain)

            // Expanded exercise detail
            if isExpanded {
                Divider()
                    .background(Color.tempoTextTertiary.opacity(0.2))

                VStack(spacing: TempoSpacing.xs) {
                    ForEach(workout.orderedExercises, id: \.id) { plannedEx in
                        exerciseDetailRow(plannedEx)
                    }
                }
                .padding(.horizontal, TempoSpacing.cardPadding)
                .padding(.vertical, TempoSpacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Exercise Detail Row

    private func exerciseDetailRow(_ plannedEx: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            HStack {
                Text(plannedEx.exercise?.name ?? "Exercise")
                    .font(.tempoBody)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                Spacer()

                // Completion indicator
                Image(systemName: plannedEx.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        plannedEx.isComplete ? Color.tempoRecoveryGreen : Color.tempoTextTertiary
                    )
            }

            // Sets detail
            HStack(spacing: TempoSpacing.xs) {
                ForEach(plannedEx.orderedSets, id: \.id) { set in
                    if set.completed, let weight = set.actualWeight, let reps = set.actualReps {
                        Text("\(Int(weight))x\(reps)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.tempoTextSecondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.tempoBgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous))
                    } else {
                        Text("--")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.tempoTextTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.tempoBgSecondary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous))
                    }
                }
            }

            // Volume for this exercise
            let vol = plannedEx.totalVolume
            if vol > 0 {
                Text("Volume: \(formatVolume(vol))")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(.vertical, TempoSpacing.xxs)
    }

    // MARK: - Helpers

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk kg", volume / 1000)
        }
        return "\(Int(volume)) kg"
    }
}
