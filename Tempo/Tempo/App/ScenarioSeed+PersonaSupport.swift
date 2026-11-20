//
// ScenarioSeed+PersonaSupport.swift
// Tempo
//
// Building blocks for the "people with history" scenarios (see
// ScenarioSeed+Personas.swift): a relative-date clock, a deterministic random
// generator, and one builder per kind of history (training, meals, recovery,
// weigh-ins, accountability). Every builder writes through the models the app
// itself reads, and records what it wrote in `PersonaFacts`, so a later
// builder (accountability, daily score) is derived from the same days instead
// of being invented separately.
//
// DEBUG only, like ScenarioSeed.
//

import Foundation
import SwiftData

#if DEBUG

    // MARK: - Clock

    /// "Days ago" arithmetic against a fixed `now`, so a persona stays valid
    /// on any day it is seeded. `daysAgo == 0` is today.
    struct PersonaClock {
        let calendar: Calendar
        let now: Date
        let today: Date

        init(now: Date = Date(), calendar: Calendar = .current) {
            self.calendar = calendar
            self.now = now
            today = calendar.startOfDay(for: now)
        }

        func day(_ daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        }

        /// A time on that day, never later than `now`.
        func time(_ daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(daysAgo)) ?? day(daysAgo)
            return min(at, now)
        }

        /// 1 = Monday … 7 = Sunday.
        func isoWeekday(_ daysAgo: Int) -> Int {
            (calendar.component(.weekday, from: day(daysAgo)) + 5) % 7 + 1
        }

        func isWeekend(_ daysAgo: Int) -> Bool {
            isoWeekday(daysAgo) >= 6
        }

        /// How many days ago this week's Monday was.
        var currentMondayDaysAgo: Int {
            isoWeekday(0) - 1
        }

        /// How many days ago the Monday of `daysAgo`'s week was.
        func mondayDaysAgo(of daysAgo: Int) -> Int {
            daysAgo + isoWeekday(daysAgo) - 1
        }

        /// 0 = this week, 1 = last week, …
        func weeksAgo(_ daysAgo: Int) -> Int {
            (mondayDaysAgo(of: daysAgo) - currentMondayDaysAgo) / 7
        }

        /// The `daysAgo` of the Monday that starts the week `weeks` weeks before this one.
        func mondayDaysAgo(weeksBack weeks: Int) -> Int {
            currentMondayDaysAgo + 7 * weeks
        }
    }

    // MARK: - Deterministic randomness

    /// SplitMix64. Seeded from the day offset and a per-persona salt, so the
    /// same persona on the same day always gets the same numbers.
    struct PersonaRNG {
        private var state: UInt64

        init(daysAgo: Int, salt: UInt64) {
            state = UInt64(bitPattern: Int64(daysAgo &* 7919 &+ 104_729)) ^ (salt &* 0x9E37_79B9_7F4A_7C15)
            _ = next()
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        /// 0 ..< 1
        mutating func unit() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }

        /// -amplitude ... +amplitude
        mutating func spread(_ amplitude: Double) -> Double {
            (unit() * 2 - 1) * amplitude
        }
    }

    // MARK: - Shared facts

    /// What the builders actually wrote, per `daysAgo`, for the ones that come after.
    struct PersonaFacts {
        var trained: Set<Int> = []
        var slotsEaten: [Int: Set<Int>] = [:]
        var recoveryScore: [Int: Double] = [:]

        func mealsEaten(_ daysAgo: Int) -> Int {
            slotsEaten[daysAgo]?.count ?? 0
        }
    }

    // MARK: - Training

    struct LiftSpec {
        let name: String
        let sets: Int
        let reps: Int
        let baseKg: Double
        let weeklyStepKg: Double
        let incrementKg: Double
    }

    struct SessionSpec {
        let isoWeekday: Int
        let type: WorkoutType
        let lifts: [LiftSpec]
        let startHour: Int
    }

    /// One planned week of lifting. `deloadEvery`: every Nth week is run at 90%.
    struct TrainingSpec {
        let sessions: [SessionSpec]
        var deloadEvery = 4
        var weightScale = 1.0

        func session(on isoWeekday: Int) -> SessionSpec? {
            sessions.first { $0.isoWeekday == isoWeekday }
        }

        var trainingWeekdays: Set<Int> {
            Set(sessions.map(\.isoWeekday))
        }
    }

    @MainActor
    enum PersonaTraining {
        static func exercise(named name: String, in context: ModelContext) -> Exercise {
            let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            if let found = all.first(where: { $0.name == name }) {
                return found
            }
            // The library is bundled and loaded at launch; this is only the
            // fallback for a bare test container.
            if all.isEmpty {
                try? ExerciseLibraryLoader.loadIfNeeded(context: context)
                if let found = ((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).first(where: { $0.name == name }) {
                    return found
                }
            }
            let created = Exercise(
                name: name, muscleGroup: .fullBody, equipment: .barbell,
                movementPattern: .squat, isCompound: true
            )
            context.insert(created)
            return created
        }

        static func weekIndex(_ clock: PersonaClock, daysAgo: Int, firstDaysAgo: Int) -> Int {
            max(0, clock.weeksAgo(firstDaysAgo) - clock.weeksAgo(daysAgo))
        }

        static func load(_ lift: LiftSpec, week: Int, spec: TrainingSpec) -> Double {
            var kg = (lift.baseKg + lift.weeklyStepKg * Double(week)) * spec.weightScale
            if spec.deloadEvery > 0, week % spec.deloadEvery == spec.deloadEvery - 1 {
                kg *= 0.9
            }
            let step = max(lift.incrementKg, 0.5)
            return max(step, (kg / step).rounded() * step)
        }

        /// Seeds completed sessions for every day in `oldest ... newest`
        /// (daysAgo, `oldest` is the larger number) that falls on a training
        /// weekday and isn't skipped. PRs come from the app's own
        /// `TrainingEngine.detectPersonalRecord`, set by set in order, exactly
        /// as logging a workout does.
        ///
        /// `partialOn`: a day whose session was cut short — only that many
        /// working sets get logged (then the rest is marked pain-skipped).
        @discardableResult
        static func seed(
            context: ModelContext,
            clock: PersonaClock,
            spec: TrainingSpec,
            oldest: Int,
            newest: Int,
            salt: UInt64,
            facts: inout PersonaFacts,
            skip: (_ daysAgo: Int) -> Bool = { _ in false },
            partial: (daysAgo: Int, session: SessionSpec, workingSets: Int)? = nil
        ) -> [WorkoutPlan] {
            let engine = TrainingEngine()
            var plans: [WorkoutPlan] = []
            var cache: [String: Exercise] = [:]
            func lookup(_ name: String) -> Exercise {
                if let hit = cache[name] {
                    return hit
                }
                let found = exercise(named: name, in: context)
                cache[name] = found
                return found
            }

            for daysAgo in stride(from: oldest, through: newest, by: -1) {
                let isoDay = clock.isoWeekday(daysAgo)
                var session = spec.session(on: isoDay)
                var cutShortAfter: Int?
                if let partial, partial.daysAgo == daysAgo {
                    session = partial.session
                    cutShortAfter = partial.workingSets
                } else if skip(daysAgo) {
                    session = nil
                }
                guard let session else {
                    continue
                }
                var rng = PersonaRNG(daysAgo: daysAgo, salt: salt)
                let week = weekIndex(clock, daysAgo: daysAgo, firstDaysAgo: oldest)
                let start = clock.time(daysAgo, hour: session.startHour, minute: 30)

                let plan = WorkoutPlan(date: clock.day(daysAgo), type: session.type, status: .completed)
                plan.startedAt = start
                plan.sessionRPE = 7 + Int(rng.unit() * 2.99)
                context.insert(plan)

                var cursor = start
                var loggedWorking = 0
                var order = 0
                var historyRows: [(Exercise, [PlannedSet])] = []
                var lastLiftDone = Date.distantPast

                for lift in session.lifts {
                    let ex = lookup(lift.name)
                    let planned = PlannedExercise(order: order, workoutPlan: plan, exercise: ex)
                    context.insert(planned)
                    order += 1
                    let kg = load(lift, week: week, spec: spec)
                    var sets: [PlannedSet] = []
                    var number = 1

                    if order == 1 {
                        // One warm-up ramp on the first lift; working-set filters must ignore it.
                        let warm = PlannedSet(
                            setNumber: number, targetReps: lift.reps, targetWeight: kg * 0.6,
                            actualReps: lift.reps, actualWeight: (kg * 0.6 / 2.5).rounded() * 2.5,
                            completed: true, restSeconds: 60, isWarmup: true, plannedExercise: planned
                        )
                        context.insert(warm)
                        cursor = cursor.addingTimeInterval(150)
                        warm.completedAt = cursor
                        sets.append(warm)
                        number += 1
                    }

                    for index in 0 ..< lift.sets {
                        let cutOff = cutShortAfter.map { loggedWorking >= $0 } ?? false
                        let isLast = index == lift.sets - 1
                        var reps = lift.reps
                        if isLast, rng.unit() < 0.35 {
                            reps = max(1, reps - 1)
                        }
                        let rpe = min(9, 7 + (index * 2) / max(1, lift.sets))
                        let set = PlannedSet(
                            setNumber: number, targetReps: lift.reps, targetWeight: kg, targetRIR: 2,
                            actualReps: cutOff ? nil : reps, actualWeight: cutOff ? nil : kg,
                            rpe: cutOff ? nil : rpe, completed: !cutOff, restSeconds: 120,
                            plannedExercise: planned
                        )
                        context.insert(set)
                        number += 1
                        sets.append(set)
                        guard !cutOff else {
                            planned.painSkipped = true
                            continue
                        }
                        cursor = cursor.addingTimeInterval(Double(150 + Int(rng.unit() * 60)))
                        set.completedAt = cursor
                        lastLiftDone = cursor
                        loggedWorking += 1

                        if let pr = engine.detectPersonalRecord(
                            exercise: ex, weight: kg, reps: reps, rir: set.effectiveRIR(reps: reps),
                            workoutPlanID: plan.id
                        ) {
                            pr.date = cursor
                            context.insert(pr)
                        }
                    }
                    historyRows.append((ex, sets))
                }

                let finished = lastLiftDone > .distantPast ? lastLiftDone.addingTimeInterval(240) : start.addingTimeInterval(1800)
                plan.finishedAt = finished
                plan.durationMinutes = max(1, Int(finished.timeIntervalSince(start) / 60))

                // Same snapshot the app writes when a workout finishes.
                for (ex, sets) in historyRows {
                    let done = sets.filter { $0.completed && !$0.isWarmup }
                    guard !done.isEmpty else {
                        continue
                    }
                    let best = done.max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) }
                    context.insert(ExerciseHistory(
                        date: finished,
                        estimated1RM: done.compactMap(\.estimated1RM).max(),
                        totalVolume: done.reduce(0) { $0 + ($1.volume ?? 0) },
                        bestSetWeight: best?.actualWeight,
                        bestSetReps: best?.actualReps,
                        setsPerformed: done.count,
                        workoutPlanID: plan.id,
                        exercise: ex
                    ))
                }
                facts.trained.insert(daysAgo)
                plans.append(plan)
            }
            return plans
        }
    }

    // MARK: - Weigh-ins

    struct WeighInSpec {
        /// Weight on the trend line today.
        let endKg: Double
        let kgPerWeek: Double
        let isoWeekdays: Set<Int>
        let bodyFatPercent: Double
        var noiseKg = 0.25
    }

    @MainActor
    enum PersonaWeighIns {
        static func series(clock: PersonaClock, spec: WeighInSpec, oldest: Int, newest: Int, salt: UInt64) -> [(daysAgo: Int, kg: Double)] {
            var out: [(Int, Double)] = []
            for daysAgo in stride(from: oldest, through: newest, by: -1) where spec.isoWeekdays.contains(clock.isoWeekday(daysAgo)) {
                var rng = PersonaRNG(daysAgo: daysAgo, salt: salt)
                let kg = spec.endKg - spec.kgPerWeek * Double(daysAgo) / 7 + rng.spread(spec.noiseKg)
                out.append((daysAgo, (kg * 10).rounded() / 10))
            }
            return out
        }

        /// One BodyComposition per weigh-in, the same row HealthKit's daily snapshot writes.
        @discardableResult
        static func seed(
            context: ModelContext, clock: PersonaClock, spec: WeighInSpec,
            oldest: Int, newest: Int, salt: UInt64
        ) -> Double? {
            let rows = series(clock: clock, spec: spec, oldest: oldest, newest: newest, salt: salt)
            for row in rows {
                var rng = PersonaRNG(daysAgo: row.daysAgo, salt: salt &+ 17)
                let fat = ((spec.bodyFatPercent + rng.spread(0.3)) * 10).rounded() / 10
                let at = clock.time(row.daysAgo, hour: 7, minute: 10)
                context.insert(BodyComposition(
                    date: clock.day(row.daysAgo),
                    weightKg: row.kg,
                    bodyFatPercent: fat,
                    leanMassKg: ((row.kg * (1 - fat / 100)) * 10).rounded() / 10,
                    measurementDate: at,
                    capturedAt: at
                ))
            }
            return rows.last?.kg
        }
    }

    // MARK: - Recovery

    struct RecoverySpec {
        var baseHRV: Double
        var baseRHR: Double
        var baseSleep: Double
        /// Pushes scores toward green; with 14 about 80% of days are green.
        var greenBias: Double = 14
        /// 0 ... 1: how hard the week is hitting (cuts sleep and HRV, lifts RHR).
        var stress: (Int) -> Double = { _ in 0 }
        var baseStrainKcal = 2600.0
        /// Lowest score allowed on a day (lets a persona open on a green morning).
        var minScore: (Int) -> Double = { _ in 0 }
    }

    @MainActor
    enum PersonaRecovery {
        static func seed(
            context: ModelContext, clock: PersonaClock, spec: RecoverySpec,
            oldest: Int, newest: Int, salt: UInt64, facts: inout PersonaFacts
        ) {
            let need = 8.0
            var deficits: [Double] = []
            for daysAgo in stride(from: oldest, through: newest, by: -1) {
                var rng = PersonaRNG(daysAgo: daysAgo, salt: salt)
                let stress = spec.stress(daysAgo)
                var sleep = min(9.2, max(3.8, spec.baseSleep + rng.spread(0.6) - 2.4 * stress))
                var hrv = spec.baseHRV * (1 + rng.spread(0.11) - 0.38 * stress)
                if spec.minScore(daysAgo) > 0 {
                    // A pinned good morning: HRV and sleep at or above baseline so every number agrees.
                    hrv = max(hrv, spec.baseHRV * 1.03)
                    sleep = max(sleep, spec.baseSleep + 0.2)
                }
                let rhr = spec.baseRHR + rng.spread(2) + 9 * stress
                let score = max(spec.minScore(daysAgo), min(
                    99,
                    max(3, (58 + spec.greenBias + (hrv - spec.baseHRV) / spec.baseHRV * 95 + (sleep - spec.baseSleep) * 7).rounded())
                ))

                let totalMin = sleep * 60
                let awake = Int(28 + 22 * stress + rng.unit() * 8)
                let deep = Int(totalMin * (0.19 - 0.04 * stress))
                let rem = Int(totalMin * (0.22 - 0.03 * stress))
                let light = max(0, Int(totalMin) - deep - rem)
                let trained = facts.trained.contains(daysAgo)
                let strain = (trained ? 11.5 + rng.unit() * 3.5 : 5 + rng.unit() * 3) * (1 - 0.15 * stress)

                deficits.append(max(0, need - sleep))
                let debt = deficits.suffix(3).reduce(0, +)

                let row = DailyRecovery(
                    date: clock.day(daysAgo),
                    recoveryScore: score,
                    hrvRmssd: (hrv * 10).rounded() / 10,
                    restingHR: rhr.rounded(),
                    spo2: 96 + (rng.unit() * 2).rounded(),
                    skinTemp: 33.4 + rng.spread(0.3) + 0.4 * stress,
                    sleepHours: (sleep * 100).rounded() / 100,
                    sleepScore: min(100, max(30, (sleep / need * 100 - 4 * stress).rounded())),
                    sleepEfficiency: (91 - 7 * stress + rng.spread(2)).rounded(),
                    sleepConsistency: (86 - 20 * stress + rng.spread(4)).rounded(),
                    deepSleepMin: deep,
                    remSleepMin: rem,
                    lightSleepMin: light,
                    awakeMin: awake,
                    sleepNeededBaseline: need,
                    sleepDebt: (debt * 10).rounded() / 10,
                    respiratoryRate: 14.4 + rng.spread(0.4) + 0.8 * stress,
                    strain: (strain * 10).rounded() / 10,
                    avgHR: trained ? 112 : 88,
                    maxHR: trained ? 168 + rng.unit() * 14 : 128,
                    caloriesBurned: (spec.baseStrainKcal + strain * 65).rounded()
                )
                context.insert(row)
                facts.recoveryScore[daysAgo] = score
            }
        }
    }

    // MARK: - Food and meals

    struct FoodSpec {
        let name: String
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    struct MealItem {
        let food: FoodSpec
        let grams: Double
    }

    struct MealTemplate {
        let items: [MealItem]

        var kcal: Double {
            items.reduce(0) { $0 + $1.food.kcal * $1.grams / 100 }
        }
    }

    struct DietSpec {
        let breakfasts: [MealTemplate]
        let lunches: [MealTemplate]
        let snacks: [MealTemplate]
        let dinners: [MealTemplate]

        func templates(slot: Int) -> [MealTemplate] {
            switch slot {
            case 1: breakfasts
            case 2: lunches
            case 3: snacks
            default: dinners
            }
        }
    }

    struct NutritionSpec {
        let diet: DietSpec
        let dailyKcal: Double
        let oldest: Int
        let newest: Int
        let salt: UInt64
        /// Training weekdays, for the plan's day types.
        let trainingWeekdays: Set<Int>
        /// Which meal slots (1 ... 4) were eaten on a day before today. Empty = not logged.
        let slotsEaten: (Int) -> Set<Int>
        /// How many of today's meals are eaten (slots 1 ... n).
        let todayEaten: Int
        /// This week's plan is live (covers today, future days planned).
        let currentWeekActive: Bool
        /// Eaten portions vary around the plan by up to this fraction.
        var portionNoise = 0.03
    }

    @MainActor
    enum PersonaMeals {
        static let slotNames = ["Breakfast", "Lunch", "Snack", "Dinner"]
        static let slotTimes = [(8, 0), (12, 30), (16, 30), (19, 30)]
        static let slotShares = [0.25, 0.30, 0.15, 0.30]

        static func roundedGrams(_ value: Double) -> Double {
            max(5, (value / 5).rounded() * 5)
        }

        static func foods(_ template: MealTemplate, scale: Double) -> [PlannedFood] {
            template.items.map { item in
                let grams = roundedGrams(item.grams * scale)
                let factor = grams / 100
                return PlannedFood(
                    name: item.food.name,
                    quantityGrams: grams,
                    calories: (item.food.kcal * factor).rounded(),
                    proteinG: (item.food.protein * factor * 10).rounded() / 10,
                    carbsG: (item.food.carbs * factor * 10).rounded() / 10,
                    fatG: (item.food.fat * factor * 10).rounded() / 10
                )
            }
        }

        /// What one planned day looks like (the numbers its target is made of).
        static func plannedDay(_ spec: NutritionSpec, daysAgo: Int) -> [(slot: Int, template: MealTemplate, scale: Double)] {
            (1 ... 4).map { slot in
                let options = spec.diet.templates(slot: slot)
                let template = options[abs(daysAgo &* 3 &+ slot) % options.count]
                let scale = spec.dailyKcal * slotShares[slot - 1] / max(1, template.kcal)
                return (slot, template, scale)
            }
        }

        /// `PlannedMeal` rows grouped into one `WeeklyMealPlan` per Monday-week.
        static func seed(
            context: ModelContext, clock: PersonaClock, spec: NutritionSpec, facts: inout PersonaFacts
        ) {
            let firstMonday = clock.mondayDaysAgo(of: spec.oldest)
            // Past the last logged day there is no plan unless this week's is live.
            let lastMonday = spec.currentWeekActive ? clock.currentMondayDaysAgo : clock.mondayDaysAgo(of: max(spec.newest, 0))
            var mondayAgo = firstMonday
            while mondayAgo >= lastMonday {
                let isCurrent = mondayAgo == clock.currentMondayDaysAgo
                let active = isCurrent && spec.currentWeekActive
                var assignments: [Int: String] = [:]
                for iso in 1 ... 7 {
                    assignments[iso] = (spec.trainingWeekdays.contains(iso) ? DayType.strength : DayType.rest).rawValue
                }
                let plan = WeeklyMealPlan(
                    startDate: clock.day(mondayAgo),
                    endDate: clock.day(mondayAgo - 6),
                    dayTypeAssignments: assignments,
                    isActive: active,
                    generatedAt: clock.time(mondayAgo + 1, hour: 19)
                )
                plan.isArchived = !active
                context.insert(plan)

                for offset in 0 ..< 7 {
                    let daysAgo = mondayAgo - offset
                    let isFuture = daysAgo < 0
                    if isFuture, !active {
                        continue
                    }
                    if !isFuture, daysAgo > spec.oldest || daysAgo < spec.newest {
                        continue
                    }
                    var eaten: Set<Int> = []
                    if daysAgo > 0 {
                        eaten = spec.slotsEaten(daysAgo)
                    } else if daysAgo == 0, spec.todayEaten > 0 {
                        eaten = Set(1 ... min(4, spec.todayEaten))
                    }
                    if daysAgo >= 0 {
                        facts.slotsEaten[daysAgo] = eaten
                    }
                    var rng = PersonaRNG(daysAgo: daysAgo, salt: spec.salt)
                    for entry in plannedDay(spec, daysAgo: daysAgo) {
                        let planned = foods(entry.template, scale: entry.scale)
                        let (hour, minute) = slotTimes[entry.slot - 1]
                        let meal = PlannedMeal(
                            dayDate: clock.day(daysAgo),
                            mealNumber: entry.slot,
                            mealName: slotNames[entry.slot - 1],
                            scheduledTime: String(format: "%02d:%02d", hour, minute),
                            foods: planned,
                            totalCalories: planned.reduce(0) { $0 + $1.calories },
                            totalProtein: planned.reduce(0) { $0 + $1.proteinG },
                            totalCarbs: planned.reduce(0) { $0 + $1.carbsG },
                            totalFat: planned.reduce(0) { $0 + $1.fatG },
                            status: .planned,
                            mealPlan: plan
                        )
                        context.insert(meal)
                        meal.capturePlanBaselineIfNeeded()
                        guard eaten.contains(entry.slot) else {
                            continue
                        }
                        // Eaten a little off the plan: portions drift, the target (baseline) doesn't.
                        let eatenScale = entry.scale * (1 + rng.spread(spec.portionNoise))
                        let actual = foods(entry.template, scale: eatenScale)
                        meal.foods = actual
                        meal.recalculateTotals()
                        meal.status = .eaten
                        meal.actualEatenAt = clock.time(daysAgo, hour: hour, minute: minute + Int(rng.unit() * 20))
                    }
                }
                mondayAgo -= 7
            }
        }
    }

    // MARK: - Accountability

    struct AccountabilitySpec {
        var studyTargetMinutes = 120.0
        var subjects: [String]
        /// Training only counts on these days (Monday = bit 0).
        var trainingDays: ActiveDays
        /// Study minutes done on a past day.
        var studyMinutes: (Int) -> Int
        /// Study target for that day (weekend halving and exam boost already applied).
        var studyTarget: (Int) -> Double
        /// Today's study minutes so far.
        var todayStudyMinutes = 50
        let oldest: Int
        let newest: Int
        /// Past days with an explicit "missed" outcome beyond what the facts say.
        var forcedMiss: (Int) -> Bool = { _ in false }
        /// False when the app hasn't been opened today (nothing logged since).
        var includeToday = true
    }

    @MainActor
    enum PersonaAccountability {
        static let mealsTarget = 3.0

        /// Non-negotiables, one DailyAccountability per day (past days and today),
        /// study sessions that add up to each day's study minutes, and the
        /// overall + per-habit streaks computed from those same days.
        static func seed(
            context: ModelContext, clock: PersonaClock, spec: AccountabilitySpec, facts: PersonaFacts
        ) {
            let study = NonNegotiable(name: "Study", type: .study, targetValue: spec.studyTargetMinutes, trackingMethod: .timer, order: 0)
            let train = NonNegotiable(
                name: "Training",
                type: .train,
                targetValue: 1,
                trackingMethod: .manual,
                activeDays: spec.trainingDays,
                order: 1
            )
            let meals = NonNegotiable(name: "Meals", type: .meals, targetValue: mealsTarget, trackingMethod: .manual, order: 2)
            for nn in [study, train, meals] {
                nn.createdAt = clock.day(spec.oldest)
                context.insert(nn)
            }

            var overall: [Bool?] = []
            var perHabit: [StreakType: [Bool?]] = [.study: [], .training: [], .meals: []]

            for daysAgo in stride(from: spec.oldest, through: 0, by: -1) {
                let isToday = daysAgo == 0
                if isToday ? !spec.includeToday : daysAgo < spec.newest {
                    continue
                }
                let studyMin = isToday ? spec.todayStudyMinutes : spec.studyMinutes(daysAgo)
                let trained = facts.trained.contains(daysAgo)
                let mealCount = facts.mealsEaten(daysAgo)
                let trainingActive = spec.trainingDays.isActive(on: clock.calendar.component(.weekday, from: clock.day(daysAgo)))
                let studyTarget = spec.studyTarget(daysAgo)

                let da = DailyAccountability(date: clock.day(daysAgo))
                context.insert(da)
                let forced = spec.forcedMiss(daysAgo) && !isToday
                var results: [(nn: NonNegotiable, current: Double, target: Double, done: Bool, type: StreakType)] = [
                    (study, Double(studyMin), studyTarget, Double(studyMin) >= studyTarget && !forced, .study),
                    (meals, Double(mealCount), mealsTarget, Double(mealCount) >= mealsTarget && !forced, .meals),
                ]
                if trainingActive {
                    results.insert((train, trained ? 1 : 0, 1, trained && !forced, .training), at: 1)
                }
                for result in results {
                    context.insert(NonNegotiableProgress(
                        date: clock.day(daysAgo), currentValue: result.current, targetValue: result.target,
                        isCompleted: result.done,
                        completedAt: result.done ? clock.time(daysAgo, hour: 20) : nil,
                        nonNegotiable: result.nn, dailyAccountability: da
                    ))
                }
                da.totalStudyMinutes = studyMin
                let doneCount = results.filter(\.done).count
                da.accountabilityScore = Int((Double(doneCount) / Double(results.count) * 100).rounded())
                let allDone = doneCount == results.count
                if !isToday {
                    da.leisureUnlocked = allDone
                    da.unlockedAt = allDone ? clock.time(daysAgo, hour: 20, minute: 15) : nil
                    overall.append(allDone)
                    for result in results {
                        perHabit[result.type, default: []].append(result.done)
                    }
                    if !trainingActive {
                        perHabit[.training, default: []].append(nil)
                    }
                }
                seedSessions(
                    context: context, clock: clock, daysAgo: daysAgo, minutes: studyMin,
                    subjects: spec.subjects, accountability: da
                )
            }

            func streak(_ type: StreakType, _ days: [Bool?], lastDay: Int) -> Streak {
                var current = 0
                var longest = 0
                var run = 0
                for day in days {
                    switch day {
                    case true?:
                        run += 1
                        longest = max(longest, run)
                    case false?:
                        run = 0
                    case nil:
                        break
                    }
                }
                // Trailing run only counts while it reaches yesterday.
                if lastDay <= 1 {
                    current = run
                }
                let row = Streak(type: type, currentCount: current, longestCount: max(longest, current))
                let lastCompletedAgo = (0 ..< days.count).reversed().first { days[$0] == true }.map { lastDay + (days.count - 1 - $0) }
                row.lastCompletedDate = lastCompletedAgo.map { clock.day($0) }
                return row
            }

            let lastDay = spec.newest
            for row in [
                streak(.overall, overall, lastDay: lastDay),
                streak(.study, perHabit[.study] ?? [], lastDay: lastDay),
                streak(.training, perHabit[.training] ?? [], lastDay: lastDay),
                streak(.meals, perHabit[.meals] ?? [], lastDay: lastDay),
            ] {
                context.insert(row)
            }
        }

        /// Chunks that add up exactly to `minutes`, shaped like real sessions.
        static func seedSessions(
            context: ModelContext, clock: PersonaClock, daysAgo: Int, minutes: Int,
            subjects: [String], accountability: DailyAccountability
        ) {
            guard minutes > 0, !subjects.isEmpty else {
                return
            }
            let chunks = [50, 90, 25, 50, 60]
            var remaining = minutes
            var index = 0
            var hour = 14
            while remaining > 0 {
                let length = min(remaining, chunks[(index + daysAgo) % chunks.count])
                let start = clock.time(daysAgo, hour: hour, minute: (index * 7) % 30)
                let deep = length >= 60
                var rng = PersonaRNG(daysAgo: daysAgo &* 31 &+ index, salt: 99)
                let session = StudySession(
                    startTime: start,
                    endTime: start.addingTimeInterval(Double(length) * 60),
                    durationMinutes: length,
                    subject: subjects[(index + abs(daysAgo)) % subjects.count],
                    sessionType: deep ? .deepWork : .pomodoro,
                    focusScore: 72 + Int(rng.unit() * 24),
                    distractions: Int(rng.unit() * 4),
                    completedPomodoros: deep ? 0 : max(1, length / 25),
                    dailyAccountability: accountability
                )
                context.insert(session)
                remaining -= length
                index += 1
                hour += 2
            }
        }
    }

    // MARK: - Daily score trend

    @MainActor
    enum PersonaScores {
        /// The Dashboard's 7-day score sparkline reads these. Blend of the same
        /// facts the other builders wrote, so the trend follows the data.
        static func seed(context: ModelContext, clock: PersonaClock, facts: PersonaFacts, oldest: Int, newest: Int) {
            for daysAgo in stride(from: oldest, through: max(newest, 1), by: -1) {
                let recovery = facts.recoveryScore[daysAgo] ?? 60
                let meals = Double(facts.mealsEaten(daysAgo)) / 4 * 100
                let move = facts.trained.contains(daysAgo) ? 100.0 : 55.0
                let score = Int((0.4 * recovery + 0.3 * meals + 0.3 * move).rounded())
                context.insert(DailyScoreEntry(date: clock.day(daysAgo), score: min(100, max(0, score))))
            }
        }
    }

    // MARK: - Foods

    enum PersonaFoods {
        static let oats = FoodSpec(name: "oats", kcal: 389, protein: 16.9, carbs: 66, fat: 6.9)
        static let wholeMilk = FoodSpec(name: "whole milk", kcal: 61, protein: 3.2, carbs: 4.8, fat: 3.3)
        static let banana = FoodSpec(name: "banana", kcal: 89, protein: 1.1, carbs: 23, fat: 0.3)
        static let blueberries = FoodSpec(name: "blueberries", kcal: 57, protein: 0.7, carbs: 14, fat: 0.3)
        static let eggs = FoodSpec(name: "eggs", kcal: 143, protein: 13, carbs: 1.1, fat: 9.5)
        static let wholeWheatBread = FoodSpec(name: "whole wheat bread", kcal: 247, protein: 13, carbs: 41, fat: 3.4)
        static let avocado = FoodSpec(name: "avocado", kcal: 160, protein: 2, carbs: 9, fat: 15)
        static let greekYogurt = FoodSpec(name: "greek yogurt", kcal: 97, protein: 9, carbs: 3.6, fat: 5)
        static let honey = FoodSpec(name: "honey", kcal: 304, protein: 0.3, carbs: 82, fat: 0)
        static let whey = FoodSpec(name: "whey protein", kcal: 400, protein: 80, carbs: 8, fat: 6)
        static let chickenBreast = FoodSpec(name: "chicken breast", kcal: 165, protein: 31, carbs: 0, fat: 3.6)
        static let whiteRice = FoodSpec(name: "white rice", kcal: 130, protein: 2.7, carbs: 28, fat: 0.3)
        static let broccoli = FoodSpec(name: "broccoli", kcal: 34, protein: 2.8, carbs: 7, fat: 0.4)
        static let oliveOil = FoodSpec(name: "olive oil", kcal: 884, protein: 0, carbs: 0, fat: 100)
        static let salmon = FoodSpec(name: "salmon", kcal: 208, protein: 20, carbs: 0, fat: 13)
        static let sweetPotato = FoodSpec(name: "sweet potato", kcal: 86, protein: 1.6, carbs: 20, fat: 0.1)
        static let beefMince = FoodSpec(name: "lean beef mince", kcal: 215, protein: 26, carbs: 0, fat: 12)
        static let pasta = FoodSpec(name: "pasta", kcal: 158, protein: 5.8, carbs: 31, fat: 0.9)
        static let tomatoSauce = FoodSpec(name: "tomato sauce", kcal: 40, protein: 1.5, carbs: 8, fat: 0.3)
        static let tuna = FoodSpec(name: "tuna", kcal: 116, protein: 26, carbs: 0, fat: 1)
        static let peanutButter = FoodSpec(name: "peanut butter", kcal: 588, protein: 25, carbs: 20, fat: 50)

        // Vegan, free of nuts, soy, mushrooms and cilantro.
        static let oatMilk = FoodSpec(name: "oat milk", kcal: 45, protein: 1, carbs: 6.7, fat: 1.5)
        static let chia = FoodSpec(name: "chia seeds", kcal: 486, protein: 17, carbs: 42, fat: 31)
        static let peaProtein = FoodSpec(name: "pea protein", kcal: 380, protein: 80, carbs: 6, fat: 5)
        static let lentils = FoodSpec(name: "lentils", kcal: 116, protein: 9, carbs: 20, fat: 0.4)
        static let chickpeas = FoodSpec(name: "chickpeas", kcal: 164, protein: 8.9, carbs: 27, fat: 2.6)
        static let blackBeans = FoodSpec(name: "black beans", kcal: 132, protein: 8.9, carbs: 24, fat: 0.5)
        static let quinoa = FoodSpec(name: "quinoa", kcal: 120, protein: 4.4, carbs: 21, fat: 1.9)
        static let brownRice = FoodSpec(name: "brown rice", kcal: 123, protein: 2.7, carbs: 26, fat: 1)
        static let spinach = FoodSpec(name: "spinach", kcal: 23, protein: 2.9, carbs: 3.6, fat: 0.4)
        static let tomato = FoodSpec(name: "tomato", kcal: 18, protein: 0.9, carbs: 3.9, fat: 0.2)
        static let seitan = FoodSpec(name: "seitan", kcal: 140, protein: 25, carbs: 5, fat: 2)
        static let hummus = FoodSpec(name: "hummus", kcal: 166, protein: 8, carbs: 14, fat: 10)
        static let wholeWheatPasta = FoodSpec(name: "whole wheat pasta", kcal: 150, protein: 6, carbs: 30, fat: 1)
        static let sunflowerButter = FoodSpec(name: "sunflower seed butter", kcal: 617, protein: 21, carbs: 20, fat: 55)
        static let carrots = FoodSpec(name: "carrots", kcal: 41, protein: 0.9, carbs: 10, fat: 0.2)

        static func meal(_ items: [(FoodSpec, Double)]) -> MealTemplate {
            MealTemplate(items: items.map { MealItem(food: $0.0, grams: $0.1) })
        }

        static let omnivore = DietSpec(
            breakfasts: [
                meal([(oats, 90), (wholeMilk, 250), (banana, 120), (whey, 30)]),
                meal([(eggs, 200), (wholeWheatBread, 100), (avocado, 80), (blueberries, 100)]),
            ],
            lunches: [
                meal([(chickenBreast, 200), (whiteRice, 300), (broccoli, 150), (oliveOil, 10)]),
                meal([(beefMince, 180), (pasta, 300), (tomatoSauce, 120)]),
            ],
            snacks: [
                meal([(greekYogurt, 250), (honey, 20), (banana, 120)]),
                meal([(wholeWheatBread, 80), (peanutButter, 30), (banana, 100)]),
            ],
            dinners: [
                meal([(salmon, 180), (sweetPotato, 300), (broccoli, 150), (oliveOil, 8)]),
                meal([(chickenBreast, 220), (whiteRice, 280), (broccoli, 150), (oliveOil, 10)]),
                meal([(tuna, 150), (pasta, 250), (oliveOil, 10), (tomatoSauce, 100)]),
            ]
        )

        static let vegan = DietSpec(
            breakfasts: [
                meal([(oats, 80), (oatMilk, 300), (banana, 120), (chia, 15), (peaProtein, 25), (blueberries, 80)]),
                meal([(wholeWheatBread, 100), (avocado, 100), (chickpeas, 100), (tomato, 100)]),
            ],
            lunches: [
                meal([(lentils, 250), (brownRice, 200), (spinach, 80), (oliveOil, 10)]),
                meal([(chickpeas, 200), (quinoa, 200), (hummus, 50), (tomato, 100), (spinach, 60)]),
                meal([(seitan, 150), (wholeWheatPasta, 250), (tomatoSauce, 150), (broccoli, 100)]),
            ],
            snacks: [
                meal([(banana, 120), (sunflowerButter, 20)]),
                meal([(hummus, 60), (carrots, 100), (wholeWheatBread, 40)]),
            ],
            dinners: [
                meal([(blackBeans, 250), (brownRice, 200), (avocado, 80), (tomato, 100)]),
                meal([(seitan, 180), (sweetPotato, 300), (broccoli, 150), (oliveOil, 8)]),
                meal([(lentils, 250), (wholeWheatPasta, 200), (tomatoSauce, 100), (spinach, 80)]),
            ]
        )

        /// Words that must never appear in a vegan-persona meal.
        static let veganForbidden = [
            "chicken", "beef", "salmon", "tuna", "egg", "whey", "honey", "whole milk", "yogurt", "cheese", "butter ",
            "tofu", "soy", "tempeh", "mushroom", "cilantro", "peanut", "almond", "cashew", "walnut", "hazelnut", "pistachio", "pecan",
        ]
    }

#endif
