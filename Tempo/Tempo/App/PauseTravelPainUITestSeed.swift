//
// PauseTravelPainUITestSeed.swift
// Tempo
//
// Pause/travel-pain feature — DEBUG-only seeding for screenshots, same
// pattern as `WeeklyUploadUITestSeed.swift`/`GuidedRunUITestSeed.swift`. Two
// independent scenarios (a pause and a travel/pain state can't both be
// "today" at once — a pause blocks the whole day):
// - `--uitesting-pause-active`: an active pause covering today, on top of a
//   fixed-mode program — Today shows the "Paused — recover" card.
// - `--uitesting-travel-pain`: an active travel-equipment period (dumbbells
//   only) on a fixed-mode program whose today session uses a barbell lift
//   (so it shows a "Hotel swap" label), plus a recent pain report on that
//   same exercise (caution chip) and enough football/pause/pain history in
//   the current week for the trainer report's new sections to have content.
//

import Foundation
import SwiftData

#if DEBUG
    enum PauseTravelPainUITestSeed {
        static let pauseActiveArgument = "--uitesting-pause-active"
        static let travelPainArgument = "--uitesting-travel-pain"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            if ProcessInfo.processInfo.arguments.contains(pauseActiveArgument) {
                seedPauseActive(context: context)
            }
            if ProcessInfo.processInfo.arguments.contains(travelPainArgument) {
                seedTravelPain(context: context)
            }
        }

        // MARK: - Shared cleanup

        private static func clearLeftoverState(context: ModelContext) {
            for old in (try? context.fetch(FetchDescriptor<TrainerProgram>())) ?? [] {
                context.delete(old)
            }
            for old in (try? context.fetch(FetchDescriptor<TrainingPause>())) ?? [] {
                context.delete(old)
            }
            for old in (try? context.fetch(FetchDescriptor<TravelEquipmentPeriod>())) ?? [] {
                context.delete(old)
            }
            for old in (try? context.fetch(FetchDescriptor<PainReport>())) ?? [] {
                context.delete(old)
            }
            for old in (try? context.fetch(FetchDescriptor<Match>())) ?? [] {
                context.delete(old)
            }
            let dayStart = Calendar.current.startOfDay(for: Date())
            let weekAgo = Calendar.current.date(byAdding: .day, value: -8, to: dayStart) ?? dayStart
            let weekAhead = Calendar.current.date(byAdding: .day, value: 8, to: dayStart) ?? dayStart
            let plans = (try? context.fetch(FetchDescriptor<WorkoutPlan>(
                predicate: #Predicate { $0.date >= weekAgo && $0.date < weekAhead }
            ))) ?? []
            for plan in plans {
                context.delete(plan)
            }
        }

        // MARK: - Fixed-mode program fixture

        private static func fixedProgram(startDate: Date) -> TrainerProgram {
            let today = Date()
            let weekday = TrainerProgram.isoWeekday(of: today)
            let day = ProgramDay(
                weekday: weekday,
                title: "Push Day",
                focus: WorkoutType.push.rawValue,
                exercises: [
                    ProgramExercise(name: "Barbell Bench Press", sets: 3, repsLow: 8),
                    ProgramExercise(name: "Romanian Deadlift", sets: 3, repsLow: 10),
                ],
                notes: "UI test fixture"
            )
            return TrainerProgram(
                name: "Coach Marco",
                startDate: startDate,
                weeks: [ProgramWeek(days: [day])],
                repeats: true,
                isActive: true,
                sourceKind: "text",
                scheduleMode: .fixed
            )
        }

        // MARK: - Scenario 1: active pause

        @MainActor
        private static func seedPauseActive(context: ModelContext) {
            clearLeftoverState(context: context)
            let today = Calendar.current.startOfDay(for: Date())
            let program = fixedProgram(startDate: Calendar.current.date(byAdding: .day, value: -21, to: today) ?? today)
            context.insert(program)

            let pause = TrainingPause(
                reason: .sick,
                startDate: today,
                plannedEndDate: Calendar.current.date(byAdding: .day, value: 2, to: today),
                programIDAtPause: program.id,
                scheduleModeAtPause: .fixed
            )
            context.insert(pause)
            try? context.save()
        }

        // MARK: - Scenario 2: travel + pain

        @MainActor
        private static func seedTravelPain(context: ModelContext) {
            clearLeftoverState(context: context)
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let program = fixedProgram(startDate: cal.date(byAdding: .day, value: -21, to: today) ?? today)
            context.insert(program)

            let period = TravelEquipmentPeriod(
                scope: .thisWeek,
                availableEquipment: [.dumbbell, .bodyweight, .resistanceBand],
                startDate: today
            )
            context.insert(period)

            // A match earlier this week (football section) + a resolved
            // 2-day pause earlier this week (pauses section) — both inside
            // the report's default "this week" scope.
            let monday = TrainingCalendar.mondayOfWeek(containing: today)
            if let matchDay = cal.date(byAdding: .day, value: 1, to: monday), matchDay < today {
                context.insert(Match(kickoff: matchDay, opponent: "Inter Miami", isCompetitive: true))
            }
            if monday < today {
                let pauseEnd = cal.date(byAdding: .day, value: 1, to: monday) ?? monday
                if pauseEnd < today {
                    let resolvedPause = TrainingPause(reason: .injured, startDate: monday, plannedEndDate: pauseEnd)
                    resolvedPause.resumedAt = cal.date(byAdding: .day, value: 1, to: pauseEnd)
                    context.insert(resolvedPause)
                }
            }
            context.insert(PainReport(
                date: cal.date(byAdding: .day, value: -1, to: today) ?? today,
                bodyArea: .knee, severity: 6,
                exerciseNameSnapshot: "Romanian Deadlift", actionTaken: .swapped
            ))
            try? context.save()
        }
    }
#endif
