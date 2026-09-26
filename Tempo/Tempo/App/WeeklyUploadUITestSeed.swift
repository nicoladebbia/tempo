//
// WeeklyUploadUITestSeed.swift
// Tempo
//
// Weekly-upload feature — DEBUG-only seeding for a UI test/screenshot run
// that needs to see the "New week — upload" card without waiting for a real
// Sunday 19:00. Inserts an ACTIVE weekly-cadence TrainerProgram whose served
// week is several weeks in the past — `TrainerProgramWeeklyUpload.isDue`
// reads true for ANY `now` once that fixed deadline has passed (see its
// header), so this is due immediately at whatever real time the test runs.
//

import Foundation
import SwiftData

#if DEBUG
    enum WeeklyUploadUITestSeed {
        static let launchArgument = "--uitesting-weekly-upload-due"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains(launchArgument) else {
                return
            }
            let today = Date()
            let weekday = TrainerProgram.isoWeekday(of: today)
            let staleMonday = Calendar.current.date(byAdding: .day, value: -21, to: TrainingCalendar.mondayOfWeek(containing: today))
                ?? today

            let day = ProgramDay(
                weekday: weekday,
                title: "Lifting 2",
                focus: WorkoutType.fullBody.rawValue,
                exercises: [ProgramExercise(name: "Bench Press", exerciseID: nil, sets: 3, repsLow: 8)],
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
            try? context.save()
        }
    }
#endif
