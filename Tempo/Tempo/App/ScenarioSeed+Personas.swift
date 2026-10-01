//
// ScenarioSeed+Personas.swift
// Tempo
//
// "People with history": scenarios that look like someone who has used the
// app for weeks, so trend charts, streaks, history screens, PR detection,
// recovery trends and adherence numbers have real data behind them. Each one
// is built from the generic builders in ScenarioSeed+PersonaSupport.swift
// (all dates relative to `now`, all numbers deterministic).
//
// Whoop: nothing here pretends to be a Whoop connection. The Recovery and
// Training screens read `DailyRecovery` history directly, so those show the
// seeded trend. The Dashboard Body quadrant reads live Whoop/HealthKit only,
// so on a simulator it shows its "not connected" state whatever is seeded.
//
// DEBUG only, like ScenarioSeed.
//

import Foundation
import SwiftData

#if DEBUG
    extension ScenarioSeed {
        enum Persona {
            case athlete
            case pickyVegan
            case examWeek
            case injured
            case lapsedPro
        }

        @MainActor
        static func seedPersona(_ persona: Persona, context: ModelContext, now: Date = Date()) {
            let clock = PersonaClock(now: now)
            switch persona {
            case .athlete: athlete(context, clock)
            case .pickyVegan: pickyVegan(context, clock)
            case .examWeek: examWeek(context, clock)
            case .injured: injured(context, clock)
            case .lapsedPro: lapsedPro(context, clock)
            }
            try? context.save()
        }

        // MARK: - Shared helpers

        /// Daily calories the Fuel setup would aim at for this body and goal.
        private static func dailyKcal(
            weightKg: Double, heightCm: Double, age: Int, sex: BiologicalSex,
            trainingDays: Int, goal: DietaryGoal, goalWeightKg: Double?, weeklyRateKg: Double?
        ) -> Double {
            Double(TDEECalculator.calculate(
                weightKg: weightKg, heightCm: heightCm, age: age, biologicalSex: sex,
                bodyFatPercent: nil, trainingFrequency: trainingDays, whoopAverageTDEE: nil,
                goal: goal, goalWeightKg: goalWeightKg, weeklyRateKg: weeklyRateKg
            ).adjustedCalories)
        }

        /// Gym slot on the given ISO weekdays (Monday = 1); every other day free.
        private static func routine(trainingOn days: Set<Int>, startMinutes: Int, wakeWeekday: Int = 7 * 60) -> WeeklyRoutine {
            var routine = WeeklyRoutine(days: (1 ... 7).map { DayRoutine(weekday: $0) })
            for weekday in 1 ... 7 {
                var day = routine[weekday]
                day.wakeMinutes = weekday <= 5 ? wakeWeekday : 9 * 60
                day.bedMinutes = 23 * 60
                if days.contains(weekday) {
                    day.training = TrainingSlot(startMinutes: startMinutes, durationMinutes: 70, kind: "gym")
                }
                routine[weekday] = day
            }
            return routine
        }

        /// Days with one meal left out (the snack) so adherence reads ~95%, not 100%.
        private static func mostlyLogged(everyNth n: Int, offset: Int) -> (Int) -> Set<Int> {
            { daysAgo in (daysAgo * 7 + offset) % n == 0 ? [1, 2, 4] : [1, 2, 3, 4] }
        }

        private static let upperA = SessionSpec(isoWeekday: 1, type: .upper, lifts: [
            LiftSpec(name: "Barbell Bench Press", sets: 4, reps: 6, baseKg: 77.5, weeklyStepKg: 1.25, incrementKg: 1.25),
            LiftSpec(name: "Barbell Row", sets: 4, reps: 8, baseKg: 67.5, weeklyStepKg: 1.25, incrementKg: 1.25),
            LiftSpec(name: "Overhead Press", sets: 3, reps: 8, baseKg: 42.5, weeklyStepKg: 0.75, incrementKg: 1.25),
            LiftSpec(name: "Lat Pulldown", sets: 3, reps: 10, baseKg: 60, weeklyStepKg: 1.25, incrementKg: 2.5),
            LiftSpec(name: "Tricep Pushdown", sets: 3, reps: 12, baseKg: 30, weeklyStepKg: 1.25, incrementKg: 2.5),
        ], startHour: 17)

        private static let lowerA = SessionSpec(isoWeekday: 2, type: .lower, lifts: [
            LiftSpec(name: "Barbell Back Squat", sets: 4, reps: 5, baseKg: 100, weeklyStepKg: 2.5, incrementKg: 2.5),
            LiftSpec(name: "Romanian Deadlift", sets: 3, reps: 8, baseKg: 90, weeklyStepKg: 2.5, incrementKg: 2.5),
            LiftSpec(name: "Leg Press", sets: 3, reps: 10, baseKg: 180, weeklyStepKg: 5, incrementKg: 5),
            LiftSpec(name: "Seated Leg Curl", sets: 3, reps: 12, baseKg: 45, weeklyStepKg: 1.25, incrementKg: 2.5),
            LiftSpec(name: "Standing Calf Raise", sets: 4, reps: 12, baseKg: 70, weeklyStepKg: 2.5, incrementKg: 2.5),
        ], startHour: 17)

        private static let upperB = SessionSpec(isoWeekday: 4, type: .upper, lifts: [
            LiftSpec(name: "Incline Dumbbell Press", sets: 3, reps: 8, baseKg: 30, weeklyStepKg: 1, incrementKg: 1),
            LiftSpec(name: "Seated Cable Row", sets: 3, reps: 10, baseKg: 55, weeklyStepKg: 1.25, incrementKg: 2.5),
            LiftSpec(name: "Dumbbell Shoulder Press", sets: 3, reps: 10, baseKg: 22, weeklyStepKg: 0.5, incrementKg: 1),
            LiftSpec(name: "Lateral Raise", sets: 4, reps: 15, baseKg: 9, weeklyStepKg: 0.25, incrementKg: 1),
            LiftSpec(name: "Hammer Curl", sets: 3, reps: 10, baseKg: 16, weeklyStepKg: 0.5, incrementKg: 1),
            LiftSpec(name: "Skull Crusher", sets: 3, reps: 10, baseKg: 30, weeklyStepKg: 1.25, incrementKg: 2.5),
        ], startHour: 17)

        private static let lowerB = SessionSpec(isoWeekday: 5, type: .lower, lifts: [
            LiftSpec(name: "Conventional Deadlift", sets: 3, reps: 5, baseKg: 125, weeklyStepKg: 2.5, incrementKg: 2.5),
            LiftSpec(name: "Front Squat", sets: 3, reps: 6, baseKg: 75, weeklyStepKg: 2.5, incrementKg: 2.5),
            LiftSpec(name: "Walking Lunge", sets: 3, reps: 12, baseKg: 22, weeklyStepKg: 1, incrementKg: 2),
            LiftSpec(name: "Hip Thrust", sets: 3, reps: 10, baseKg: 100, weeklyStepKg: 5, incrementKg: 5),
            LiftSpec(name: "Seated Calf Raise", sets: 3, reps: 15, baseKg: 45, weeklyStepKg: 2.5, incrementKg: 2.5),
        ], startHour: 17)

        /// Mon / Tue / Thu / Fri upper-lower, matching the Fuel setup's gym days.
        static let fourDaySplit = TrainingSpec(sessions: [upperA, lowerA, upperB, lowerB])

        /// Mon / Wed / Fri full body, a lighter lifter.
        static let threeDayFullBody = TrainingSpec(sessions: [
            SessionSpec(isoWeekday: 1, type: .fullBody, lifts: [
                LiftSpec(name: "Goblet Squat", sets: 3, reps: 10, baseKg: 20, weeklyStepKg: 1, incrementKg: 2),
                LiftSpec(name: "Dumbbell Flat Bench Press", sets: 3, reps: 10, baseKg: 18, weeklyStepKg: 0.5, incrementKg: 1),
                LiftSpec(name: "Seated Cable Row", sets: 3, reps: 10, baseKg: 40, weeklyStepKg: 1.25, incrementKg: 2.5),
                LiftSpec(name: "Dumbbell Shoulder Press", sets: 3, reps: 10, baseKg: 12, weeklyStepKg: 0.5, incrementKg: 1),
            ], startHour: 18),
            SessionSpec(isoWeekday: 3, type: .fullBody, lifts: [
                LiftSpec(name: "Leg Press", sets: 3, reps: 10, baseKg: 100, weeklyStepKg: 5, incrementKg: 5),
                LiftSpec(name: "Dumbbell Romanian Deadlift", sets: 3, reps: 10, baseKg: 20, weeklyStepKg: 1, incrementKg: 2),
                LiftSpec(name: "Lat Pulldown", sets: 3, reps: 10, baseKg: 45, weeklyStepKg: 1.25, incrementKg: 2.5),
                LiftSpec(name: "Hip Thrust", sets: 3, reps: 10, baseKg: 60, weeklyStepKg: 2.5, incrementKg: 2.5),
            ], startHour: 18),
            SessionSpec(isoWeekday: 5, type: .fullBody, lifts: [
                LiftSpec(name: "Barbell Back Squat", sets: 3, reps: 8, baseKg: 60, weeklyStepKg: 2.5, incrementKg: 2.5),
                LiftSpec(name: "Incline Dumbbell Press", sets: 3, reps: 10, baseKg: 16, weeklyStepKg: 0.5, incrementKg: 1),
                LiftSpec(name: "Chest Supported Row", sets: 3, reps: 10, baseKg: 35, weeklyStepKg: 1.25, incrementKg: 2.5),
                LiftSpec(name: "Hammer Curl", sets: 3, reps: 12, baseKg: 10, weeklyStepKg: 0.5, incrementKg: 1),
            ], startHour: 18),
        ], deloadEvery: 4)

        // MARK: - athlete

        @MainActor
        private static func athlete(_ context: ModelContext, _ clock: PersonaClock) {
            let oldest = clock.mondayDaysAgo(weeksBack: 8)
            var facts = PersonaFacts()
            let salt: UInt64 = 11

            let weighIns = WeighInSpec(endKg: 82.0, kgPerWeek: 0.25, isoWeekdays: [1, 3, 6], bodyFatPercent: 14.8)
            let latestKg = PersonaWeighIns.series(clock: clock, spec: weighIns, oldest: oldest, newest: 0, salt: salt).last?.kg ?? 82
            let kcal = dailyKcal(
                weightKg: latestKg, heightCm: 183, age: 22, sex: .male, trainingDays: 4,
                goal: .leanGain, goalWeightKg: 85, weeklyRateKg: 0.25
            )

            fuelReady(context) { draft in
                draft.weightKg = latestKg
            }
            if let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first {
                settings.experienceLevelRaw = "Intermediate"
            }

            PersonaWeighIns.seed(context: context, clock: clock, spec: weighIns, oldest: oldest, newest: 0, salt: salt)
            PersonaTraining.seed(
                context: context, clock: clock, spec: fourDaySplit, oldest: oldest, newest: 1, salt: salt, facts: &facts
            )
            PersonaMeals.seed(
                context: context, clock: clock,
                spec: NutritionSpec(
                    diet: PersonaFoods.omnivore, dailyKcal: kcal, oldest: oldest, newest: 0, salt: salt,
                    trainingWeekdays: fourDaySplit.trainingWeekdays,
                    slotsEaten: mostlyLogged(everyNth: 20, offset: 3), todayEaten: 2, currentWeekActive: true
                ),
                facts: &facts
            )
            PersonaRecovery.seed(
                context: context, clock: clock,
                spec: RecoverySpec(baseHRV: 72, baseRHR: 51, baseSleep: 7.7),
                oldest: oldest, newest: 0, salt: salt, facts: &facts
            )
            PersonaAccountability.seed(
                context: context, clock: clock,
                spec: AccountabilitySpec(
                    subjects: ["Algorithms", "Economics"],
                    trainingDays: ActiveDays(rawValue: ActiveDays.monday.rawValue | ActiveDays.tuesday.rawValue | ActiveDays.thursday
                        .rawValue | ActiveDays.friday.rawValue),
                    studyMinutes: { clock.isWeekend($0) ? 70 : 125 + ($0 * 13) % 40 },
                    studyTarget: { clock.isWeekend($0) ? 60 : 120 },
                    oldest: oldest, newest: 1,
                    // Missed one day early on, so the streak has a start.
                    forcedMiss: { $0 == oldest - 5 }
                ),
                facts: facts
            )
            PersonaScores.seed(context: context, clock: clock, facts: facts, oldest: min(oldest, 29), newest: 1)
        }

        // MARK: - picky-vegan

        @MainActor
        private static func pickyVegan(_ context: ModelContext, _ clock: PersonaClock) {
            let oldest = clock.mondayDaysAgo(weeksBack: 3)
            var facts = PersonaFacts()
            let salt: UInt64 = 23
            let trainingDays: Set = [1, 3, 5]

            let weighIns = WeighInSpec(endKg: 64.0, kgPerWeek: 0, isoWeekdays: [1, 4], bodyFatPercent: 24, noiseKg: 0.3)
            let latestKg = PersonaWeighIns.series(clock: clock, spec: weighIns, oldest: oldest, newest: 0, salt: salt).last?.kg ?? 64
            let kcal = dailyKcal(
                weightKg: latestKg, heightCm: 168, age: 26, sex: .female, trainingDays: 3,
                goal: .maintain, goalWeightKg: nil, weeklyRateKg: nil
            )

            fuelReady(context, pantryRows: veganPantry) { draft in
                draft.weightKg = latestKg
                draft.heightCm = 168
                draft.age = 26
                draft.sex = .female
                draft.goal = .maintain
                draft.goalWeightKg = nil
                draft.weeklyRateKg = nil
                draft.restrictions = [.vegan, .nutFree]
                draft.allergies = ["peanuts", "tree nuts"]
                draft.dislikedFoods = ["soy", "tofu", "tempeh", "mushrooms", "cilantro", "eggplant", "olives"]
                draft.favoriteFoods = ["lentils", "chickpeas", "sweet potato"]
                draft.weeklyBudgetUSD = 70
                draft.stores = ["Whole Foods"]
                draft.routine = routine(trainingOn: trainingDays, startMinutes: 18 * 60)
            }

            PersonaWeighIns.seed(context: context, clock: clock, spec: weighIns, oldest: oldest, newest: 0, salt: salt)
            var light = threeDayFullBody
            light.deloadEvery = 0
            light.weightScale = 0.7
            PersonaTraining.seed(
                context: context, clock: clock, spec: light, oldest: oldest, newest: 1, salt: salt, facts: &facts
            )
            PersonaMeals.seed(
                context: context, clock: clock,
                spec: NutritionSpec(
                    diet: PersonaFoods.vegan, dailyKcal: kcal, oldest: oldest, newest: 0, salt: salt,
                    trainingWeekdays: trainingDays,
                    slotsEaten: mostlyLogged(everyNth: 20, offset: 6), todayEaten: 2, currentWeekActive: true
                ),
                facts: &facts
            )
            PersonaRecovery.seed(
                context: context, clock: clock,
                spec: RecoverySpec(baseHRV: 68, baseRHR: 58, baseSleep: 7.6, greenBias: 12, baseStrainKcal: 2100),
                oldest: oldest, newest: 0, salt: salt, facts: &facts
            )
            PersonaScores.seed(context: context, clock: clock, facts: facts, oldest: min(oldest, 29), newest: 1)
        }

        private static let veganPantry: [PantryRow] = [
            ("lentils", "Green Lentils (dry)", 1000, .grams, .pantry),
            ("chickpeas", "Chickpeas", 4, .cans, .pantry),
            ("black beans", "Black Beans", 3, .cans, .pantry),
            ("brown rice", "Brown Rice", 2000, .grams, .pantry),
            ("quinoa", "Quinoa", 500, .grams, .pantry),
            ("oats", "Rolled Oats", 1000, .grams, .pantry),
            ("oat milk", "Oat Milk", 2, .liters, .fridge),
            ("whole wheat pasta", "Whole Wheat Pasta", 750, .grams, .pantry),
            ("seitan", "Seitan", 400, .grams, .fridge),
            ("hummus", "Hummus", 300, .grams, .fridge),
            ("spinach", "Baby Spinach", 250, .grams, .fridge),
            ("sweet potato", "Sweet Potatoes", 1200, .grams, .pantry),
            ("banana", "Bananas", 6, .pieces, .pantry),
            ("chia seeds", "Chia Seeds", 300, .grams, .cupboard),
            ("pea protein", "Pea Protein", 800, .grams, .cupboard),
            ("sunflower seed butter", "Sunflower Seed Butter", 1, .jars, .cupboard),
            ("olive oil", "Olive Oil", 1, .bottles, .cupboard),
        ]

        // MARK: - exam-week

        @MainActor
        private static func examWeek(_ context: ModelContext, _ clock: PersonaClock) {
            let oldest = clock.mondayDaysAgo(weeksBack: 4)
            var facts = PersonaFacts()
            let salt: UInt64 = 37
            let trainingDays: Set = [1, 3, 5]
            /// The crunch: today and the five days before it.
            func stress(_ daysAgo: Int) -> Double {
                [0: 0.95, 1: 0.85, 2: 0.7, 3: 0.55, 4: 0.4, 5: 0.25][daysAgo] ?? 0
            }

            let weighIns = WeighInSpec(endKg: 71.0, kgPerWeek: 0, isoWeekdays: [1, 5], bodyFatPercent: 16)
            let latestKg = PersonaWeighIns.series(clock: clock, spec: weighIns, oldest: oldest, newest: 0, salt: salt).last?.kg ?? 71
            let kcal = dailyKcal(
                weightKg: latestKg, heightCm: 178, age: 21, sex: .male, trainingDays: 3,
                goal: .maintain, goalWeightKg: nil, weeklyRateKg: nil
            )

            fuelReady(context) { draft in
                draft.weightKg = latestKg
                draft.heightCm = 178
                draft.age = 21
                draft.goal = .maintain
                draft.goalWeightKg = nil
                draft.weeklyRateKg = nil
                draft.dislikedFoods = []
                draft.weeklyBudgetUSD = 60
                draft.routine = routine(trainingOn: trainingDays, startMinutes: 17 * 60, wakeWeekday: 8 * 60)
            }
            if let settings = (try? context.fetch(FetchDescriptor<UserSettings>()))?.first {
                settings.examMode = true
                settings.examModeEndDate = clock.day(-4)
            }

            PersonaWeighIns.seed(context: context, clock: clock, spec: weighIns, oldest: oldest, newest: 0, salt: salt)
            PersonaTraining.seed(
                context: context, clock: clock, spec: threeDayFullBody, oldest: oldest, newest: 1, salt: salt, facts: &facts,
                // Fewer workouts once the crunch starts.
                skip: { $0 <= 3 }
            )
            PersonaMeals.seed(
                context: context, clock: clock,
                spec: NutritionSpec(
                    diet: PersonaFoods.omnivore, dailyKcal: kcal, oldest: oldest, newest: 0, salt: salt,
                    trainingWeekdays: trainingDays,
                    slotsEaten: { daysAgo in
                        // Skipping breakfast and the snack when the crunch hits.
                        if daysAgo <= 3 {
                            return [2, 4]
                        }
                        if daysAgo <= 5 {
                            return [1, 2, 4]
                        }
                        return [1, 2, 3, 4]
                    },
                    todayEaten: 0, currentWeekActive: true
                ),
                facts: &facts
            )
            PersonaRecovery.seed(
                context: context, clock: clock,
                spec: RecoverySpec(baseHRV: 66, baseRHR: 56, baseSleep: 7.4, greenBias: 12, stress: stress, baseStrainKcal: 2400),
                oldest: oldest, newest: 0, salt: salt, facts: &facts
            )
            PersonaAccountability.seed(
                context: context, clock: clock,
                spec: AccountabilitySpec(
                    subjects: ["Calculus II", "Organic Chemistry", "Physics"],
                    trainingDays: ActiveDays(rawValue: ActiveDays.monday.rawValue | ActiveDays.wednesday.rawValue | ActiveDays.friday
                        .rawValue),
                    studyMinutes: { daysAgo in
                        if daysAgo <= 5 {
                            return clock.isWeekend(daysAgo) ? 150 : 230 + (daysAgo * 17) % 50
                        }
                        return clock.isWeekend(daysAgo) ? 65 : 115 + (daysAgo * 11) % 30
                    },
                    // Same rule the engine applies: weekends halve, an exam within a week adds 50%.
                    studyTarget: { daysAgo in
                        let base = clock.isWeekend(daysAgo) ? 60.0 : 120.0
                        return daysAgo <= 3 ? base * 1.5 : base
                    },
                    todayStudyMinutes: 95,
                    oldest: oldest, newest: 1
                ),
                facts: facts
            )
            PersonaScores.seed(context: context, clock: clock, facts: facts, oldest: min(oldest, 29), newest: 1)
        }

        // MARK: - injured

        @MainActor
        private static func injured(_ context: ModelContext, _ clock: PersonaClock) {
            let oldest = clock.mondayDaysAgo(weeksBack: 6)
            let injuryDay = 4
            var facts = PersonaFacts()
            let salt: UInt64 = 53
            /// Sleep and HRV dip for a few days after the injury.
            func stress(_ daysAgo: Int) -> Double {
                [0: 0.2, 1: 0.25, 2: 0.3, 3: 0.4, 4: 0.45][daysAgo] ?? 0
            }

            let weighIns = WeighInSpec(endKg: 82.0, kgPerWeek: 0.2, isoWeekdays: [1, 3, 6], bodyFatPercent: 15)
            let latestKg = PersonaWeighIns.series(clock: clock, spec: weighIns, oldest: oldest, newest: 0, salt: salt).last?.kg ?? 82
            let kcal = dailyKcal(
                weightKg: latestKg, heightCm: 183, age: 22, sex: .male, trainingDays: 4,
                goal: .leanGain, goalWeightKg: 85, weeklyRateKg: 0.25
            )

            fuelReady(context) { draft in
                draft.weightKg = latestKg
            }

            PersonaWeighIns.seed(context: context, clock: clock, spec: weighIns, oldest: oldest, newest: 0, salt: salt)
            // Normal training up to the injury; that day's session is a lower day cut short on squats.
            PersonaTraining.seed(
                context: context, clock: clock, spec: fourDaySplit, oldest: oldest, newest: injuryDay, salt: salt, facts: &facts,
                partial: (daysAgo: injuryDay, session: lowerA, workingSets: 2)
            )
            PersonaMeals.seed(
                context: context, clock: clock,
                spec: NutritionSpec(
                    diet: PersonaFoods.omnivore, dailyKcal: kcal, oldest: oldest, newest: 0, salt: salt,
                    trainingWeekdays: fourDaySplit.trainingWeekdays,
                    slotsEaten: mostlyLogged(everyNth: 20, offset: 9), todayEaten: 2, currentWeekActive: true
                ),
                facts: &facts
            )
            PersonaRecovery.seed(
                context: context, clock: clock,
                spec: RecoverySpec(baseHRV: 72, baseRHR: 51, baseSleep: 7.6, stress: stress),
                oldest: oldest, newest: 0, salt: salt, facts: &facts
            )
            PersonaAccountability.seed(
                context: context, clock: clock,
                spec: AccountabilitySpec(
                    subjects: ["Algorithms", "Economics"],
                    trainingDays: ActiveDays(rawValue: ActiveDays.monday.rawValue | ActiveDays.tuesday.rawValue | ActiveDays.thursday
                        .rawValue | ActiveDays.friday.rawValue),
                    studyMinutes: { clock.isWeekend($0) ? 70 : 125 + ($0 * 13) % 40 },
                    studyTarget: { clock.isWeekend($0) ? 60 : 120 },
                    oldest: oldest, newest: 1
                ),
                facts: facts
            )
            PersonaScores.seed(context: context, clock: clock, facts: facts, oldest: min(oldest, 29), newest: 1)

            // The injury itself: a pain report on the squat, follow-ups as it eased, and a pause.
            let squat = PersonaTraining.exercise(named: "Barbell Back Squat", in: context)
            let reports: [(daysAgo: Int, severity: Int, action: PainActionTaken, note: String)] = [
                (injuryDay, 7, .endedSession, "Sharp pain in the right knee on the way up, set 3. Stopped the session."),
                (2, 5, .none, "Still sore on stairs. No swelling."),
                (1, 4, .none, "Better this morning. Walking is fine."),
            ]
            for report in reports {
                context.insert(PainReport(
                    date: clock.time(report.daysAgo, hour: report.daysAgo == injuryDay ? 18 : 9, minute: 20),
                    bodyArea: .knee, severity: report.severity,
                    exerciseID: squat.id, exerciseNameSnapshot: squat.name,
                    actionTaken: report.action, note: report.note,
                    createdAt: clock.time(report.daysAgo, hour: report.daysAgo == injuryDay ? 18 : 9, minute: 20)
                ))
            }
            context.insert(TrainingPause(
                reason: .injured,
                startDate: clock.day(injuryDay),
                plannedEndDate: clock.day(-10),
                createdAt: clock.time(injuryDay, hour: 18, minute: 40)
            ))
        }

        // MARK: - lapsed-pro

        @MainActor
        private static func lapsedPro(_ context: ModelContext, _ clock: PersonaClock) {
            let lastDay = 22
            let oldest = lastDay + 70
            var facts = PersonaFacts()
            let salt: UInt64 = 71

            // Cutting: 88.5 kg ten weeks ago to 84.5 on the last day they weighed in.
            let weighIns = WeighInSpec(
                endKg: 84.5 + 0.4 * Double(lastDay) / 7, kgPerWeek: -0.4,
                isoWeekdays: [2, 4, 6], bodyFatPercent: 19, noiseKg: 0.3
            )
            let latestKg = PersonaWeighIns.series(clock: clock, spec: weighIns, oldest: oldest, newest: lastDay, salt: salt).last?
                .kg ?? 84.5
            let kcal = dailyKcal(
                weightKg: latestKg, heightCm: 180, age: 28, sex: .male, trainingDays: 4,
                goal: .cut, goalWeightKg: 80, weeklyRateKg: 0.4
            )

            fuelReady(context, pantryRows: [
                ("chicken breast", "Chicken Breast", 800, .grams, .fridge),
                ("white rice", "White Rice", 1500, .grams, .pantry),
                ("oats", "Rolled Oats", 700, .grams, .pantry),
                ("eggs", "Eggs", 6, .pieces, .fridge),
                ("greek yogurt", "Greek Yogurt", 500, .grams, .fridge),
                ("broccoli", "Broccoli", 300, .grams, .fridge),
                ("banana", "Bananas", 4, .pieces, .pantry),
            ]) { draft in
                draft.weightKg = latestKg
                draft.heightCm = 180
                draft.age = 28
                draft.goal = .cut
                draft.goalWeightKg = 80
                draft.weeklyRateKg = 0.4
            }
            // Bought just before they stopped; the fresh things went off weeks ago.
            for item in (try? context.fetch(FetchDescriptor<PantryItem>())) ?? [] {
                item.purchaseDate = clock.day(lastDay + 2)
                if [.fridge].contains(item.storageLocation) {
                    item.useBy = clock.day(lastDay - 8)
                }
            }

            PersonaWeighIns.seed(context: context, clock: clock, spec: weighIns, oldest: oldest, newest: lastDay, salt: salt)
            var spec = fourDaySplit
            spec.weightScale = 0.92
            PersonaTraining.seed(
                context: context, clock: clock, spec: spec, oldest: oldest, newest: lastDay, salt: salt, facts: &facts,
                skip: { clock.weeksAgo($0) == 6 && clock.isoWeekday($0) == 4 }
            )
            PersonaMeals.seed(
                context: context, clock: clock,
                spec: NutritionSpec(
                    diet: PersonaFoods.omnivore, dailyKcal: kcal, oldest: oldest, newest: lastDay, salt: salt,
                    trainingWeekdays: fourDaySplit.trainingWeekdays,
                    slotsEaten: mostlyLogged(everyNth: 12, offset: 5), todayEaten: 0, currentWeekActive: false
                ),
                facts: &facts
            )
            PersonaRecovery.seed(
                context: context, clock: clock,
                spec: RecoverySpec(baseHRV: 62, baseRHR: 55, baseSleep: 7.2, greenBias: 10, baseStrainKcal: 2700),
                oldest: oldest, newest: lastDay, salt: salt, facts: &facts
            )
            PersonaAccountability.seed(
                context: context, clock: clock,
                spec: AccountabilitySpec(
                    subjects: ["Statistics", "Databases"],
                    trainingDays: ActiveDays(rawValue: ActiveDays.monday.rawValue | ActiveDays.tuesday.rawValue | ActiveDays.thursday
                        .rawValue | ActiveDays.friday.rawValue),
                    studyMinutes: { clock.isWeekend($0) ? 65 : 120 + ($0 * 9) % 35 },
                    studyTarget: { clock.isWeekend($0) ? 60 : 120 },
                    oldest: oldest, newest: lastDay,
                    forcedMiss: { $0 == oldest - 14 },
                    includeToday: false
                ),
                facts: facts
            )
            PersonaScores.seed(context: context, clock: clock, facts: facts, oldest: min(oldest, 29), newest: lastDay)
        }
    }
#endif
