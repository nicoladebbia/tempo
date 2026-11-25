//
// TodayWorkoutView+Thumbnail.swift
// Tempo
//

import SwiftUI

// MARK: - Exercise row

//
// One row of Today's exercise list: the exercise picture with its number on
// the corner, then the text column (name, prescription, zone, last sessions).
// Kept out of TodayWorkoutView.swift (already near the file-length cap) —
// mirrors the TodayWorkoutView+Equipment.swift convention. The picture is a
// sibling column of the text so the name row never gets squeezed.

extension TodayWorkoutView {
    func exerciseCardRow(exercise: Exercise?, index: Int, plannedExercise: PlannedExercise) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            exercisePicture(exercise: exercise, index: index, isDone: plannedExercise.isComplete)
            exerciseCardContent(plannedExercise: plannedExercise)
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// The picture (or a plain tile when the slot has no exercise record) and
    /// its place in the order. A finished exercise lights its number green.
    private func exercisePicture(exercise: Exercise?, index: Int, isDone: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let exercise {
                    ExerciseImageView(exercise: exercise, style: .hero)
                } else {
                    Tide.fill
                }
            }
            .frame(width: TideTrain.rowPicture, height: TideTrain.rowPicture)
            .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))

            Text("\(index)")
                .font(TideTrain.figure(.caption2, weight: .bold))
                .foregroundStyle(Tide.ink)
                .padding(.horizontal, Tide.s1)
                .frame(minWidth: Tide.s4, minHeight: Tide.s4)
                .background(isDone ? TideTrain.positive : Color.accentColor, in: .capsule)
                .offset(x: Tide.s1, y: Tide.s1)
        }
        .accessibilityHidden(true)
    }
}
