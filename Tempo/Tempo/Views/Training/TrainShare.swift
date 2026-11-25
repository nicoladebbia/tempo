//
// TrainShare.swift
// Tempo
//
// What the workout summary hands to the share card (`ShareCard.present`): a
// finished session, and a personal record it set. Only numbers read from the
// user's own session go on a card; a figure that is not known is left out.
// Kept apart from the view so the numbers are unit-tested.
//

import Foundation

enum TrainShare {
    /// The finished session as a card: how long, how many exercises and sets,
    /// and the total volume. A session shorter than a minute shows its sets
    /// as the big number instead of "0 minutes".
    static func workoutCard(
        title: String,
        elapsedSeconds: TimeInterval,
        exercises: Int,
        sets: Int,
        volumeKg: Double,
        date: Date = Date()
    ) -> ShareCardContent {
        let minutes = elapsedSeconds >= 60 ? Int((elapsedSeconds / 60).rounded()) : nil
        return .workout(
            title: title,
            minutes: minutes,
            exercises: exercises,
            sets: sets,
            volumeKg: volumeKg > 0 ? volumeKg : nil,
            date: date
        )
    }

    /// A personal record as a card: the new best in the user's unit, and the
    /// best it beat when there was one.
    static func recordCard(
        _ record: PersonalRecord,
        unit: WeightUnit,
        before: Double?,
        date: Date = Date()
    ) -> ShareCardContent {
        let value: String
        let unitText: String?
        var previous: String?
        if record.type == .mostReps {
            value = "\(Int(record.value))"
            unitText = Int(record.value) == 1 ? "rep" : "reps"
            previous = before.flatMap { $0 >= 1 ? "\(Int($0)) \(Int($0) == 1 ? "rep" : "reps")" : nil }
        } else {
            value = WeightFormat.number(kg: record.value, unit: unit)
            unitText = unit.abbreviation
            previous = before.flatMap { $0 > 0 ? WeightFormat.text(kg: $0, unit: unit) : nil }
        }
        return .record(exercise: record.displayName, value: value, unit: unitText, previous: previous, date: date)
    }

    /// The best the lift had before this session, in the unit the record is
    /// measured in (kg for the weight records, a count for most reps). nil when
    /// the lift had no earlier history or nothing comparable.
    static func previousBest(of record: PersonalRecord) -> Double? {
        guard let exercise = record.exercise else {
            return nil
        }
        let bar = TrainingEngine.PersonalRecordBaseline(exercise: exercise, excludingPlan: record.workoutPlanID)
        guard bar.exists else {
            return nil
        }
        let best: Double = switch record.type {
        case .oneRepMax: bar.bestE1RM
        case .repMax: bar.heaviestKg
        case .mostReps: Double(bar.bestBodyweightReps)
        case .volume: 0
        }
        return best > 0 ? best : nil
    }
}
