import Foundation

protocol TrainingEngineProtocol: Sendable {
    func generateWorkout(
        for date: Date,
        recoveryScore: Double?,
        footballDays: ActiveDays,
        split: TrainingSplit
    ) -> WorkoutPlan

    func adjustForRecovery(plan: WorkoutPlan, score: Double) -> WorkoutPlan

    func calculateProgressiveOverload(
        for exercise: Exercise,
        history: [ExerciseHistory]
    ) -> (weight: Double, reps: Int)

    func detectPersonalRecord(
        exercise: Exercise,
        weight: Double,
        reps: Int
    ) -> PersonalRecord?

    func generateWeekPlan(
        startDate: Date,
        recoveryScore: Double?,
        footballDays: ActiveDays,
        split: TrainingSplit
    ) -> [WorkoutPlan]
}
