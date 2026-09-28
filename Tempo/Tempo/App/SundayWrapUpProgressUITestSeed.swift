//
// SundayWrapUpProgressUITestSeed.swift
// Tempo
//
// Week-over-week progress feature — DEBUG-only seeding so a UI test/
// screenshot run can see an actual "vs last week" line in the Sunday
// wrap-up recap without logging two real weeks of training first. Same
// pattern and same due-immediately trick as `WeeklyUploadUITestSeed`
// (a stale served week reads as due for ANY `now`); this seed additionally
// plants a PRIOR and a CURRENT `ExerciseHistory` row for the same exercise
// so `WeekOverWeekProgress` has something to compare.
//

import Foundation
import SwiftData

#if DEBUG
    enum SundayWrapUpProgressUITestSeed {
        static let launchArgument = "--uitesting-wrapup-progress"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains(launchArgument) else {
                return
            }
            let today = Date()
            let weekday = TrainerProgram.isoWeekday(of: today)
            let staleMonday = Calendar.current.date(byAdding: .day, value: -21, to: TrainingCalendar.mondayOfWeek(containing: today))
                ?? today
            let currentWeekMonday = TrainingCalendar.mondayOfWeek(containing: today)
            let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: currentWeekMonday) ?? currentWeekMonday

            // Earlier UI tests on the same simulator leave programs/plans/
            // history behind — start from a clean slate (same rationale as
            // WeeklyUploadUITestSeed's own cleanup).
            for old in (try? context.fetch(FetchDescriptor<TrainerProgram>())) ?? [] {
                context.delete(old)
            }
            for old in (try? context.fetch(FetchDescriptor<WorkoutPlan>())) ?? [] {
                context.delete(old)
            }
            for old in (try? context.fetch(FetchDescriptor<ExerciseHistory>())) ?? [] {
                context.delete(old)
            }

            let exercise = Exercise(
                name: "Bench Press", muscleGroup: .chest, equipment: .barbell,
                movementPattern: .horizontalPush, isCompound: true
            )
            context.insert(exercise)

            let day = ProgramDay(
                weekday: weekday,
                title: "Lifting 2",
                focus: WorkoutType.fullBody.rawValue,
                exercises: [ProgramExercise(name: "Bench Press", exerciseID: exercise.id, sets: 3, repsLow: 8, weightKg: 65)],
                notes: "UI test fixture",
                weekdayGuessed: false
            )
            let program = TrainerProgram(
                name: "Coach — Week 3",
                startDate: staleMonday,
                weeks: [ProgramWeek(days: [day])],
                repeats: true,
                isActive: true,
                sourceKind: "text",
                cadence: .weekly
            )
            context.insert(program)

            // Prior session, two weeks back: 60kg x8.
            context.insert(ExerciseHistory(
                date: twoWeeksAgo, estimated1RM: 75, totalVolume: 1440,
                bestSetWeight: 60, bestSetReps: 8, exercise: exercise
            ))
            // This week's session: 65kg x8 — the recap's "TOP LIFTS" bullet
            // should read "Bench Press 60→65 kg (+…)".
            context.insert(ExerciseHistory(
                date: today, estimated1RM: 81, totalVolume: 1560,
                bestSetWeight: 65, bestSetReps: 8, exercise: exercise
            ))

            try? context.save()
        }
    }
#endif
