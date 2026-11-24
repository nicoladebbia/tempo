//
// TrainerPageScenarioSeed.swift
// Tempo
//
// DEBUG-only starting state for the Trainer page (`sim.sh qa --scenario
// trainer-full`): a running two-week program that is three weeks in, with most
// of its sessions logged, three batches of trainer changes in its log (one
// with a skip that was put back), a skipped day still ahead, one program
// queued to start later and two finished programs with different completion.
// Everything the page can show, so a screenshot run sees all of it.
//

import Foundation
import SwiftData

#if DEBUG
    enum TrainerPageScenarioSeed {
        @MainActor
        static func seed(context: ModelContext, now: Date = Date()) {
            let cal = Calendar.current
            let thisMonday = TrainingCalendar.mondayOfWeek(containing: now)
            func monday(weeksAgo: Int) -> Date {
                cal.date(byAdding: .day, value: -7 * weeksAgo, to: thisMonday) ?? thisMonday
            }

            // Earlier runs on this simulator leave programs and plans behind.
            for old in (try? context.fetch(FetchDescriptor<TrainerProgram>())) ?? [] {
                context.delete(old)
            }
            for old in (try? context.fetch(FetchDescriptor<WorkoutPlan>())) ?? [] {
                context.delete(old)
            }

            let active = TrainerProgram(
                name: "Coach Luca, strength block",
                startDate: monday(weeksAgo: 3),
                weeks: [week(offset: 0), week(offset: 1)],
                repeats: true,
                isActive: true,
                sourceKind: "text",
                changeLog: changeLog(now: now)
            )
            if let tomorrowSession = upcomingSession(of: active, from: now) {
                active.skippedSessions = [TrainerProgramSkip(
                    date: tomorrowSession.date,
                    sessionKey: tomorrowSession.key,
                    summary: "Legs: skipped, sore knee"
                )]
            }
            context.insert(active)
            logSessions(of: active, from: monday(weeksAgo: 3), until: now, everyOtherMissed: 5, context: context)

            let queued = TrainerProgram(
                name: "Summer cut, 6 weeks",
                startDate: cal.date(byAdding: .day, value: 10, to: now) ?? now,
                weeks: [week(offset: 0)],
                repeats: false,
                isActive: false,
                sourceKind: "text",
                queuedActivationDate: cal.date(byAdding: .day, value: 10, to: now)
            )
            context.insert(queued)

            for (name, startWeeksAgo, endWeeksAgo, missEvery) in [
                ("Off-season hypertrophy", 14, 8, 6),
                ("Pre-season conditioning", 22, 15, 3),
            ] {
                let past = TrainerProgram(
                    name: name,
                    startDate: monday(weeksAgo: startWeeksAgo),
                    weeks: [week(offset: 0), week(offset: 1)],
                    repeats: false,
                    isActive: false,
                    sourceKind: "text"
                )
                past.endedAt = monday(weeksAgo: endWeeksAgo)
                context.insert(past)
                logSessions(
                    of: past,
                    from: monday(weeksAgo: startWeeksAgo),
                    until: monday(weeksAgo: endWeeksAgo),
                    everyOtherMissed: missEvery,
                    context: context
                )
            }

            try? context.save()
        }

        // MARK: - Program shape

        /// One week: push Monday, pull Tuesday, legs Thursday, upper Saturday.
        /// The second week swaps a couple of lifts so the weeks differ.
        private static func week(offset: Int) -> ProgramWeek {
            func lift(_ name: String, sets: Int, reps: Int, kg: Double?) -> ProgramExercise {
                ProgramExercise(name: name, exerciseID: nil, sets: sets, repsLow: reps, weightKg: kg)
            }
            let push = ProgramDay(
                weekday: 1, title: "Push", focus: WorkoutType.push.rawValue,
                exercises: [
                    lift(offset == 0 ? "Bench Press" : "Incline Bench Press", sets: 4, reps: 6, kg: 80),
                    lift("Overhead Press", sets: 3, reps: 8, kg: 45),
                    lift("Triceps Pushdown", sets: 3, reps: 12, kg: 30),
                ],
                notes: nil, weekdayGuessed: false
            )
            let pull = ProgramDay(
                weekday: 2, title: "Pull", focus: WorkoutType.pull.rawValue,
                exercises: [
                    lift(offset == 0 ? "Barbell Row" : "Pull-Up", sets: 4, reps: 8, kg: offset == 0 ? 70 : nil),
                    lift("Lat Pulldown", sets: 3, reps: 10, kg: 60),
                    lift("Barbell Curl", sets: 3, reps: 10, kg: 30),
                ],
                notes: nil, weekdayGuessed: false
            )
            let legs = ProgramDay(
                weekday: 4, title: "Legs", focus: WorkoutType.legs.rawValue,
                exercises: [
                    lift("Back Squat", sets: 4, reps: 5, kg: 110),
                    lift("Romanian Deadlift", sets: 3, reps: 8, kg: 90),
                    lift("Leg Press", sets: 3, reps: 12, kg: 160),
                ],
                notes: nil, weekdayGuessed: false
            )
            let upper = ProgramDay(
                weekday: 6, title: "Upper", focus: WorkoutType.upper.rawValue,
                exercises: [
                    lift("Dumbbell Bench Press", sets: 3, reps: 10, kg: 30),
                    lift("Seated Cable Row", sets: 3, reps: 10, kg: 55),
                ],
                notes: nil, weekdayGuessed: false
            )
            return ProgramWeek(days: [push, pull, legs, upper])
        }

        private static func changeLog(now: Date) -> [TrainerProgramChangeLogEntry] {
            let cal = Calendar.current
            func daysAgo(_ days: Int) -> Date {
                cal.date(byAdding: .day, value: -days, to: now) ?? now
            }
            return [
                TrainerProgramChangeLogEntry(
                    date: daysAgo(15),
                    sourceText: "Swap incline for flat bench on Monday and add a set of rows.",
                    editSummaries: ["Mon Push: Incline Bench Press replaced by Bench Press", "Tue Pull: Barbell Row +1 set"]
                ),
                TrainerProgramChangeLogEntry(
                    date: daysAgo(8),
                    sourceText: "Drop the leg press this week, knees are tired. Skip Thursday.",
                    editSummaries: ["Thu Legs: Leg Press removed", "Thu Legs: skipped, tired knees"],
                    undoneSummaries: ["Thu Legs: skipped, tired knees"]
                ),
                TrainerProgramChangeLogEntry(
                    date: daysAgo(2),
                    sourceText: "Lighter squats at 100 kg and skip legs this week.",
                    editSummaries: ["Thu Legs: Back Squat 110 kg to 100 kg", "Thu Legs: skipped, sore knee"]
                ),
            ]
        }

        // MARK: - Logged sessions

        /// The next scheduled session on or after tomorrow, for the skipped-day row.
        private static func upcomingSession(of program: TrainerProgram, from now: Date) -> (date: Date, key: String)? {
            let cal = Calendar.current
            for offset in 1 ... 7 {
                guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)),
                      let session = program.sessions(on: day).first
                else {
                    continue
                }
                return (day, program.sessionKey(weekIndex: session.weekIndex, dayIndex: session.dayIndex))
            }
            return nil
        }

        /// A finished workout for every scheduled session between the two
        /// dates, except every `everyOtherMissed`-th one (so the completion is
        /// a believable share, not 100 percent).
        @MainActor
        private static func logSessions(
            of program: TrainerProgram,
            from start: Date,
            until end: Date,
            everyOtherMissed: Int,
            context: ModelContext
        ) {
            let cal = Calendar.current
            var day = cal.startOfDay(for: start)
            let last = cal.startOfDay(for: end)
            var index = 0
            while day < last {
                for session in program.sessions(on: day) {
                    index += 1
                    if index % everyOtherMissed == 0 {
                        continue
                    }
                    let plan = WorkoutPlan(date: day, type: session.day.workoutType, status: .completed, durationMinutes: 55)
                    plan.programSessionKey = program.sessionKey(weekIndex: session.weekIndex, dayIndex: session.dayIndex)
                    context.insert(plan)
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else {
                    break
                }
                day = next
            }
        }
    }
#endif
