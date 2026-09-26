//
// TodayWorkoutView+Thumbnail.swift
// Tempo
//

import SwiftUI

// MARK: - Exercise thumbnail row

//
// A 40x40 ExerciseImageView leading each exercise card, per
// feat/exercise-images placement (b). Kept out of TodayWorkoutView.swift
// (already near the file-length cap) — mirrors the
// TodayWorkoutView+Equipment.swift convention. Wraps the existing
// exerciseCardContent(index:plannedExercise:) unchanged (row 1's HStack is
// already tight on a small iPhone with the zone/muscle-group badges; adding
// the thumbnail as a sibling column instead of squeezing it into that row
// avoids any overflow risk there).

extension TodayWorkoutView {
    func exerciseCardRow(exercise: Exercise, index: Int, plannedExercise: PlannedExercise) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            ExerciseImageView(exercise: exercise, style: .thumbnail)
                .frame(width: 40, height: 40)

            exerciseCardContent(index: index, plannedExercise: plannedExercise)
        }
    }
}
