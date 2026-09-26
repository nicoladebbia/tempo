//
// GuidedRunUITestSeed.swift
// Tempo
//
// Guided run mode — DEBUG-only seeding for TempoUITests/Flows/GuidedRunFlowTests.
// A UI test can't sign in or run the AI program-structuring flow, so it
// can't reach an active trainer program the way a real athlete does
// (TrainerProgramImportView's DEBUG sample + save). This inserts an active
// TrainerProgram with a single Anaerobic Run day pinned to TODAY's weekday,
// plus today's WorkoutPlan pointing at it — the same shape
// `TrainerProgramSaver`/`applyTrainerProgram` would produce — so
// `TrainerSessionCard` (and its "Start guided run" button) renders on
// Today without going through sign-in. Trainer rest is set short (5s) so
// the rest screen doesn't need real time, matching --uitesting-time-scale.
//

import Foundation
import SwiftData

#if DEBUG
    enum GuidedRunUITestSeed {
        static let launchArgument = "--uitesting-guided-run-sample"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains(launchArgument) else {
                return
            }
            let today = Date()
            let weekday = TrainerProgram.isoWeekday(of: today)

            let shuttle1 = ProgramExercise(
                name: "Shuttle 1", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                weightKg: nil, rpe: 9, percentOf1RM: nil, restSeconds: 5, group: nil,
                notes: "300y total", detail: "4 reps of 25y out and back in < 65\"", perSide: nil
            )
            let shuttle2 = ProgramExercise(
                name: "Shuttle 2", exerciseID: nil, sets: 1, repsLow: 1, repsHigh: nil,
                weightKg: nil, rpe: 9, percentOf1RM: nil, restSeconds: 5, group: nil,
                notes: "320y total", detail: "4 reps 80y out and back in < 55\"", perSide: nil
            )
            let day = ProgramDay(
                weekday: weekday,
                title: "Anaerobic Run",
                focus: WorkoutType.sprint.rawValue,
                exercises: [shuttle1, shuttle2],
                notes: "UI test fixture",
                weekdayGuessed: false
            )
            let program = TrainerProgram(
                name: "UI Test Program",
                startDate: today,
                weeks: [ProgramWeek(days: [day])],
                repeats: true,
                isActive: true,
                sourceKind: "text"
            )
            context.insert(program)

            let plan = WorkoutPlan(date: today, type: .sprint)
            plan.programSessionKey = program.sessionKey(weekIndex: 0, dayIndex: 0)
            context.insert(plan)

            try? context.save()
        }
    }
#endif
