//
// DailyHydrationTarget.swift
// Tempo
//
// ONE daily hydration target for every surface (Dashboard Fuel via
// NutritionEngine, RecoverIQ prescription via RecoveryEngine).
//
//   base   = 35 ml/kg body weight (Sawka et al., 2007 ACSM), or the
//            NutritionEngine 2500 ml default when weight is unknown
//   zone   = NutritionEngine.adjustedTargets recovery-zone multipliers
//   sweat  = HydrationMath.activityBonusMl for today's logged activity
//
// The zone + sweat terms are computed BY NutritionEngine.adjustedTargets
// (hydration there depends only on base, zone, training flag and activity —
// never on the macro inputs), so this can't drift from the Dashboard formula.
// The Dashboard still passes NutritionEngine's fixed 2500 ml base; it should
// pass `baseMl(bodyWeightKg:)` so both surfaces also share the weight term.
//

import Foundation
import SwiftData

enum DailyHydrationTarget {
    /// Base when body weight is unknown — NutritionEngine's default.
    static let fallbackBaseMl = 2500

    /// Per-kg base (Sawka et al., 2007 ACSM).
    static let mlPerKg = 35.0

    /// Weight outside this range is treated as a bad reading, not a body.
    private static let plausibleWeightKg: ClosedRange<Double> = 30 ... 300

    // MARK: - Pure math

    static func baseMl(bodyWeightKg: Double?) -> Int {
        guard let kg = bodyWeightKg, plausibleWeightKg.contains(kg) else {
            return fallbackBaseMl
        }
        return Int((kg * mlPerKg).rounded())
    }

    static func targetMl(
        bodyWeightKg: Double?,
        recoveryZone: RecoveryZone?,
        isTrainingDay: Bool,
        isRestDay: Bool = false,
        activityCaloriesBurned: Double? = nil,
        activityDurationMin: Double? = nil
    ) -> Int {
        NutritionEngine.adjustedTargets(
            baseCalories: 0,
            baseProtein: 0,
            baseCarbs: 0,
            baseFat: 0,
            recoveryZone: recoveryZone,
            currentStrain: nil,
            isTrainingDay: isTrainingDay,
            isRestDay: isRestDay,
            baseHydrationMl: baseMl(bodyWeightKg: bodyWeightKg),
            activityCaloriesBurned: activityCaloriesBurned,
            activityDurationMin: activityDurationMin
        ).hydrationTargetMl
    }

    // MARK: - Inputs from the store

    /// The user's real weight: latest HealthKit body-composition snapshot,
    /// then DietaryProfile, then UserProfile. Nil → fallback base.
    @MainActor
    static func bodyWeightKg(in context: ModelContext) -> Double? {
        var compDescriptor = FetchDescriptor<BodyComposition>(
            predicate: #Predicate<BodyComposition> { $0.weightKg != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        compDescriptor.fetchLimit = 1
        if let kg = (try? context.fetch(compDescriptor))?.first?.weightKg,
           plausibleWeightKg.contains(kg)
        {
            return kg
        }
        let dietDescriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate<DietaryProfile> { $0.isActive },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let kg = (try? context.fetch(dietDescriptor))?.first?.currentWeightKg,
           plausibleWeightKg.contains(kg)
        {
            return kg
        }
        if let kg = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.weightKg,
           plausibleWeightKg.contains(kg)
        {
            return kg
        }
        return nil
    }

    /// Today's logged activity (football etc.), summed across sessions — the
    /// same query the Dashboard feeds into the sweat bonus.
    @MainActor
    static func todayActivity(
        in context: ModelContext,
        now: Date = Date()
    ) -> (caloriesBurned: Double?, durationMin: Double?) {
        let todayStart = Calendar.current.startOfDay(for: now)
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate<ActivitySession> { $0.date == todayStart }
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        let calories = sessions.compactMap(\.caloriesBurned).reduce(0, +)
        let minutes = sessions.compactMap(\.durationMinutes).reduce(0, +)
        return (calories > 0 ? calories : nil, minutes > 0 ? minutes : nil)
    }

    /// Training day per today's WorkoutPlan, mirroring the Dashboard's
    /// status mapping (planned non-rest / in progress / completed). Nil when
    /// there's no plan row for today — callers fall back to their own signal.
    @MainActor
    static func todayIsTrainingDay(in context: ModelContext, now: Date = Date()) -> Bool? {
        let today = Calendar.current.startOfDay(for: now)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return nil
        }
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { $0.date >= today && $0.date < tomorrow },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let plans = (try? context.fetch(descriptor)) ?? []
        guard let plan = plans.first(where: { $0.status == .inProgress }) ?? plans.first else {
            return nil
        }
        switch plan.status {
        case .completed,
             .inProgress: return true
        case .planned: return plan.type != .rest
        case .skipped: return false
        }
    }

    /// Full target from the store: real weight + today's activity.
    @MainActor
    static func targetMl(
        in context: ModelContext,
        recoveryZone: RecoveryZone?,
        isTrainingDay: Bool,
        now: Date = Date()
    ) -> Int {
        let activity = todayActivity(in: context, now: now)
        return targetMl(
            bodyWeightKg: bodyWeightKg(in: context),
            recoveryZone: recoveryZone,
            isTrainingDay: isTrainingDay,
            activityCaloriesBurned: activity.caloriesBurned,
            activityDurationMin: activity.durationMin
        )
    }
}
