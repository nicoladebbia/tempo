//
// MealOutcomeService.swift
// Tempo
//
// The ONE path for "I ate it / I skipped it / undo / delete" on a PlannedMeal.
// Today's card, the meal detail screen, the Watch router and the Log tab all
// call these functions (none needs a view model), so every surface applies the
// same side effects and shows the same numbers:
//
//   markEaten  status + eat time, optional substitute foods (the planned dish is
//              remembered), pantry decrement (exact detail recorded), feedback
//              row, shift of later meals, same-day macro rebalance, reminder
//              cancel, day-plan replan + `.tempoNutritionLogged`.
//   skip       status, reminders, `.tempoNutritionLogged`. Redistribution of the
//              skipped macros is the separate async `redistributeAfterSkip`.
//   undo       the inverse. A plan slot goes back to `.planned` with its original
//              planned dish and reminders; a log the user added on top of the
//              plan (`isUnplannedLog`) is REMOVED, never turned into a phantom
//              upcoming meal. Pantry is credited back exactly, the linked
//              legacy MealLog and the feedback rows are deleted, the remaining
//              meals are re-balanced.
//   restore    brings an undone/deleted log back (the 5-second Undo toast).
//

import Foundation
import os
import SwiftData

extension Notification.Name {
    /// Posted synchronously right BEFORE a meal row is deleted (userInfo
    /// `"id"`: the meal's UUID). Screens that cache `PlannedMeal` references
    /// drop it so nothing renders a deleted model.
    static let tempoMealWillBeRemoved = Notification.Name("tempo.meal.willBeRemoved")
}

@MainActor
enum MealOutcomeService {
    private static let logger = Logger(subsystem: "app.tempo", category: "MealOutcome")

    // MARK: - Types

    /// Everything the side effects need besides the meal itself.
    struct Env {
        var modelContext: ModelContext
        var notifications: (any NotificationServiceProtocol)?
        /// 7-day Whoop expenditure average + today's recovery score, so the
        /// rebalancer uses the same target as the Today ring. A nil
        /// recovery score falls back to today's stored one (`Env.live`).
        var whoopAvgTDEE: Double?
        var recoveryScore: Double?

        init(
            modelContext: ModelContext,
            notifications: (any NotificationServiceProtocol)? = nil,
            whoopAvgTDEE: Double? = nil,
            recoveryScore: Double? = nil
        ) {
            self.modelContext = modelContext
            self.notifications = notifications
            self.whoopAvgTDEE = whoopAvgTDEE
            self.recoveryScore = recoveryScore
        }

        /// The environment every non-Nutrition-tab caller (Meal detail, Watch,
        /// Coach) uses, so reminders are cancelled and the rebalance target
        /// matches the Today / Dashboard ring: reminders via the shared
        /// notification service, the 7-day Whoop TDEE from the shared Whoop
        /// service; the recovery score falls back to today's stored one.
        static func live(
            modelContext: ModelContext,
            notifications: (any NotificationServiceProtocol)?,
            whoop: (any WhoopServiceProtocol)?
        ) -> Env {
            Env(
                modelContext: modelContext,
                notifications: notifications,
                whoopAvgTDEE: whoop?.weeklyTDEEAverage,
                recoveryScore: nil
            )
        }
    }

    /// Whether and how a mark-eaten touches the pantry.
    enum PantryUse {
        /// Ate out / unknown — leave the pantry alone.
        case none
        /// Ate the planned dish: recipe ingredients (or the foods when the
        /// meal has no recipe).
        case plannedMeal
        /// Ate foods the user entered: decrement those.
        case foods
    }

    enum UndoKind: Equatable {
        /// A plan slot went back to `.planned` (planned dish restored).
        case revertedToPlanned
        /// A log on top of the plan was removed.
        case removed
    }

    /// Value copy of a log taken at undo/delete time so it can be restored.
    struct LogSnapshot {
        let kind: UndoKind
        let mealID: UUID
        let mealName: String
        let foods: [PlannedFood]
        let eatenAt: Date
        let hadMealLog: Bool
        /// `.eaten` or `.skipped`: what the meal was before the undo, so
        /// `restore` puts back exactly that (an undone skip must not become
        /// an eaten meal).
        let priorStatus: MealStatus
        let hadPantryDecrement: Bool
        let replacedPlannedDish: Bool
        let feel: MealFeel?
        let satiety: MealSatiety?
        let substituteNote: String?
    }

    // MARK: - Mark eaten

    /// Marks `meal` eaten with every side effect (see file header).
    /// - Parameters:
    ///   - foods: the foods actually eaten when they are NOT the planned dish
    ///     ("ate something else", a Quick Log landing in this slot). The
    ///     planned dish is stashed so Undo brings it back.
    ///   - mealLogID: the legacy MealLog written alongside, if any.
    /// An already-eaten meal only gets its eat time updated (never re-shifts,
    /// re-rebalances or re-decrements).
    static func markEaten(
        _ meal: PlannedMeal,
        at eatenAt: Date = Date(),
        feel: MealFeel? = nil,
        satiety: MealSatiety? = nil,
        replacingWith foods: [PlannedFood]? = nil,
        substituteNote: String? = nil,
        mealLogID: UUID? = nil,
        pantry: PantryUse = .plannedMeal,
        env: Env
    ) throws {
        let ctx = env.modelContext
        let mealID = meal.id
        logger.info("[Diag.Eat] \(meal.mealName, privacy: .private) eaten at \(eatenAt.formatted(date: .omitted, time: .shortened), privacy: .public) — \(Int(meal.totalCalories), privacy: .private)kcal pantryDecremented=\(meal.didDecrementPantry)")

        if meal.status == .eaten, foods == nil {
            meal.actualEatenAt = eatenAt
            try save(ctx)
            NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
            return
        }

        // Freeze the plan's allocation before anything rewrites the totals.
        meal.capturePlanBaselineIfNeeded()
        if let foods {
            meal.stashPlannedDishIfNeeded()
            meal.foods = foods
            meal.recalculateTotals()
        }
        meal.status = .eaten
        meal.actualEatenAt = eatenAt
        if let mealLogID {
            meal.linkedMealLogID = mealLogID
        }

        if pantry != .none, !meal.didDecrementPantry {
            let results = pantry == .plannedMeal
                ? PantryDecrementService.decrement(for: meal, modelContext: ctx)
                : PantryDecrementService.decrement(foods: meal.foods, label: meal.mealName, modelContext: ctx)
            meal.decrementDetail = results.flatMap(\.details)
            meal.didDecrementPantry = true
            PantryDepletionPlanCheck.handleDepletions(results, weeklyPlan: meal.mealPlan, modelContext: ctx)
        }

        if feel != nil || satiety != nil || substituteNote != nil {
            ctx.insert(MealFeedback(
                plannedMeal: meal,
                mealFeel: feel,
                satiety: satiety,
                substituteNote: substituteNote
            ))
        }

        if Calendar.current.isDateInToday(meal.dayDate) {
            applyMealShift(eatenMealID: mealID, eatenAt: eatenAt, env: env)
            applyMacroRebalance(env: env)
        }

        try save(ctx)
        cancelReminders(forMealID: mealID, notifications: env.notifications)
        NotificationCenter.default.post(
            name: .tempoDayPlanReplanRequested,
            object: nil,
            userInfo: ["reason": DayPlanReason.mealEatenOffSchedule.rawValue]
        )
        NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
    }

    // MARK: - Skip

    /// Marks a not-yet-eaten meal skipped. Call `redistributeAfterSkip`
    /// afterwards to spread its macros over the rest of the day.
    static func skip(_ meal: PlannedMeal, env: Env) throws {
        guard meal.status != .eaten else {
            return
        }
        meal.capturePlanBaselineIfNeeded()
        meal.status = .skipped
        meal.actualEatenAt = nil
        try save(env.modelContext)
        cancelReminders(forMealID: meal.id, notifications: env.notifications)
        NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
    }

    /// Spreads a skipped meal's macros over today's remaining planned meals
    /// (Claude when reachable, proportional fallback otherwise), applying the
    /// deltas and saving. Returns the result so the caller can say what
    /// really happened — nil when nothing was applied.
    @discardableResult
    static func redistributeAfterSkip(
        _ skipped: PlannedMeal,
        service: MealRedistributionService,
        env: Env,
        recoveryScore: Double?,
        sleepHours: Double?,
        strain: Double?,
        dayType: String
    ) async -> MealRedistributionResult? {
        guard Calendar.current.isDateInToday(skipped.dayDate) else {
            return nil
        }
        let skippedID = skipped.id
        let remaining = todaysMeals(env).filter { $0.id != skippedID }
        guard remaining.contains(where: { $0.status == .planned }) else {
            return nil
        }
        let result = await service.redistribute(
            skipped: skipped,
            remaining: remaining,
            recoveryScore: recoveryScore,
            sleepHours: sleepHours,
            strain: strain,
            dayType: dayType
        )
        // The model may have changed while the call was in flight (user
        // un-skipped it) — re-check before touching anything.
        guard skipped.status == .skipped else {
            return nil
        }
        let fresh = todaysMeals(env)
        for meal in fresh {
            meal.capturePlanBaselineIfNeeded()
        }
        let byNumber = Dictionary(result.perMeal.map { ($0.mealNumber, $0) }, uniquingKeysWith: { first, _ in first })
        var applied = false
        for meal in fresh where meal.status == .planned && meal.id != skippedID {
            guard let delta = byNumber[meal.mealNumber] else {
                continue
            }
            meal.totalCalories += delta.addCalories
            meal.totalProtein += delta.addProtein
            meal.totalCarbs += delta.addCarbs
            meal.totalFat += delta.addFat
            applied = true
        }
        guard applied else {
            return nil
        }
        do {
            try save(env.modelContext)
        } catch {
            logger.error("[Diag.Skip] redistribution save failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
        return result
    }

    // MARK: - Undo / delete

    /// The inverse of eat / skip (see file header). Returns a snapshot for `restore`.
    @discardableResult
    static func undo(_ meal: PlannedMeal, env: Env) throws -> LogSnapshot {
        let ctx = env.modelContext
        let mealID = meal.id
        let removing = meal.isUnplannedLog && meal.status == .eaten
        let feedback = feedbackRows(for: mealID, in: ctx)
        let snapshot = LogSnapshot(
            kind: removing ? .removed : .revertedToPlanned,
            mealID: mealID,
            mealName: meal.mealName,
            foods: meal.foods,
            eatenAt: meal.actualEatenAt ?? Date(),
            hadMealLog: meal.linkedMealLogID != nil,
            priorStatus: meal.status,
            hadPantryDecrement: meal.didDecrementPantry,
            replacedPlannedDish: meal.replacedPlan != nil,
            feel: feedback.first?.mealFeel,
            satiety: feedback.first?.satiety,
            substituteNote: feedback.first?.substituteNote
        )
        logger.info("[Diag.Undo] \(meal.mealName, privacy: .private) \(meal.status.rawValue, privacy: .public) → \(removing ? "removed" : "planned", privacy: .public)")

        // Credit the pantry back BEFORE foods are restored: the approximate
        // fallback derives from the foods that were eaten.
        if meal.didDecrementPantry {
            let detail = meal.decrementDetail
            if detail.isEmpty {
                _ = PantryDecrementService.credit(foods: meal.foods, label: meal.mealName, modelContext: ctx)
            } else {
                _ = PantryDecrementService.creditExact(details: detail, modelContext: ctx)
            }
            meal.decrementDetail = []
            meal.didDecrementPantry = false
        }
        deleteLinkedMealLog(of: meal, in: ctx)
        for row in feedback {
            ctx.delete(row)
        }

        if removing {
            NotificationCenter.default.post(
                name: .tempoMealWillBeRemoved,
                object: nil,
                userInfo: ["id": mealID]
            )
            ctx.delete(meal)
        } else {
            meal.restoreReplacedPlan()
            meal.status = .planned
            meal.actualEatenAt = nil
            meal.linkedMealLogID = nil
            if Calendar.current.isDateInToday(meal.dayDate) {
                // Eating/skipping moved the other meals' macros; bring them
                // back in line now that this one counts as planned again.
                applyMacroRebalance(env: env)
            }
        }
        try save(ctx)
        if !removing {
            restoreReminders(for: meal, notifications: env.notifications)
        }
        NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
        return snapshot
    }

    /// The UI's "Delete log": same effect as `undo`.
    @discardableResult
    static func deleteLog(_ meal: PlannedMeal, env: Env) throws -> LogSnapshot {
        try undo(meal, env: env)
    }

    /// Brings back a log that `undo` / `deleteLog` reverted (Undo toast).
    static func restore(_ snapshot: LogSnapshot, env: Env) throws {
        let ctx = env.modelContext
        let type = MealType.inferred(fromName: snapshot.mealName) ?? .snack
        switch snapshot.kind {
        case .removed:
            try EatenMealRecorder.record(
                snapshot.foods.map(EatenMealRecorder.input(from:)),
                type: type,
                eatenAt: snapshot.eatenAt,
                source: .manual,
                modelContext: ctx,
                notifications: env.notifications
            )
        case .revertedToPlanned:
            let id = snapshot.mealID
            var descriptor = FetchDescriptor<PlannedMeal>(predicate: #Predicate<PlannedMeal> { $0.id == id })
            descriptor.fetchLimit = 1
            guard let meal = try ctx.fetch(descriptor).first, meal.status != .eaten else {
                return
            }
            if snapshot.priorStatus == .skipped {
                try skip(meal, env: env)
                return
            }
            let logID = snapshot.hadMealLog
                ? EatenMealRecorder.makeMealLog(
                    foods: snapshot.foods, type: type, eatenAt: snapshot.eatenAt, source: .manual, in: ctx
                ).id
                : nil
            let pantry: PantryUse = snapshot.hadPantryDecrement
                ? (snapshot.replacedPlannedDish ? .foods : .plannedMeal)
                : .none
            try markEaten(
                meal,
                at: snapshot.eatenAt,
                feel: snapshot.feel,
                satiety: snapshot.satiety,
                replacingWith: snapshot.replacedPlannedDish ? snapshot.foods : nil,
                substituteNote: snapshot.substituteNote,
                mealLogID: logID,
                pantry: pantry,
                env: env
            )
        }
    }

    // MARK: - Remove one food from a logged meal

    /// Removes the food at `index` from an eaten meal that holds the user's own
    /// foods (an ad-hoc log or a replaced slot). Removing the last food undoes
    /// the whole log. Returns true when the meal itself was removed/reverted.
    @discardableResult
    static func removeFood(at index: Int, from meal: PlannedMeal, env: Env) throws -> Bool {
        var foods = meal.foods
        guard meal.status == .eaten, foods.indices.contains(index),
              meal.isUnplannedLog || meal.replacedPlan != nil
        else {
            return false
        }
        if foods.count == 1 {
            try undo(meal, env: env)
            return true
        }
        let removed = foods.remove(at: index)
        meal.foods = foods
        meal.recalculateTotals()
        if let logID = meal.linkedMealLogID {
            var descriptor = FetchDescriptor<MealLog>(predicate: #Predicate<MealLog> { $0.id == logID })
            descriptor.fetchLimit = 1
            if let log = fetchLog(descriptor, in: env.modelContext) {
                if let item = log.items.first(where: { $0.name == removed.name }) {
                    log.items.removeAll { $0.id == item.id }
                    env.modelContext.delete(item)
                }
                log.recalculateTotals()
            }
        }
        try save(env.modelContext)
        NotificationCenter.default.post(name: .tempoNutritionLogged, object: nil)
        return false
    }

    // MARK: - Presets

    /// Saves a logged meal's foods as a preset for the Log tab grid.
    @discardableResult
    static func savePreset(
        name: String,
        foods: [PlannedFood],
        mealType: MealType,
        modelContext: ModelContext
    ) throws -> MealPreset {
        let preset = MealPreset(
            name: name,
            foodItems: foods.map(EatenMealRecorder.input(from:)),
            totalCalories: foods.reduce(0) { $0 + $1.calories },
            totalProtein: foods.reduce(0) { $0 + $1.proteinG },
            totalCarbs: foods.reduce(0) { $0 + $1.carbsG },
            totalFat: foods.reduce(0) { $0 + $1.fatG },
            mealType: mealType
        )
        modelContext.insert(preset)
        try save(modelContext)
        return preset
    }

    // MARK: - Shared helpers

    /// Today's canonical meals in clock order.
    static func todaysMeals(_ env: Env) -> [PlannedMeal] {
        MealOrdering.chronological(CanonicalMeals.meals(on: Date(), in: env.modelContext))
    }

    private static func save(_ ctx: ModelContext) throws {
        do {
            try ctx.save()
        } catch {
            ctx.rollback()
            throw error
        }
    }

    private static func cancelReminders(forMealID id: UUID, notifications: (any NotificationServiceProtocol)?) {
        notifications?.cancelDefrostReminders(forMealID: id)
        notifications?.cancelPrepStartReminder(forMealID: id)
        notifications?.cancelOverdueMealReminder(forMealID: id)
    }

    /// Re-arms a reverted meal's reminders when its scheduled time is still ahead.
    private static func restoreReminders(for meal: PlannedMeal, notifications: (any NotificationServiceProtocol)?) {
        guard let notifications,
              let scheduled = PlannedMealTimingMatcher.scheduledDate(for: meal, on: meal.dayDate),
              scheduled > Date()
        else {
            return
        }
        scheduleReminders(for: meal, at: scheduled, notifications: notifications)
    }

    private static func scheduleReminders(
        for meal: PlannedMeal,
        at scheduled: Date,
        notifications: any NotificationServiceProtocol
    ) {
        notifications.scheduleMealReminder(mealName: meal.mealName, time: scheduled.addingTimeInterval(-5 * 60))
        notifications.scheduleOverdueMealReminder(
            mealID: meal.id,
            mealName: meal.mealName,
            scheduledTime: scheduled,
            lateMinutes: 15
        )
        let lead = (meal.recipe?.prepMinutes ?? 0) + (meal.recipe?.cookMinutes ?? 0)
        if lead > 0,
           let prepStart = Calendar.current.date(byAdding: .minute, value: -lead, to: scheduled),
           prepStart > Date()
        {
            notifications.schedulePrepStartReminder(mealID: meal.id, mealName: meal.mealName, prepStartDate: prepStart)
        }
    }

    private static func feedbackRows(for mealID: UUID, in ctx: ModelContext) -> [MealFeedback] {
        // Predicate on the relationship id — iterating rows and reading
        // `row.plannedMeal?.id` crashes on a dangling ref (see
        // NutritionTabViewModel.refreshFeedbackPresence).
        let descriptor = FetchDescriptor<MealFeedback>(
            predicate: #Predicate<MealFeedback> { row in row.plannedMeal?.id == mealID }
        )
        do {
            return try ctx.fetch(descriptor)
        } catch {
            logger.error("[Diag.Undo] feedback fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func fetchLog(_ descriptor: FetchDescriptor<MealLog>, in ctx: ModelContext) -> MealLog? {
        do {
            return try ctx.fetch(descriptor).first
        } catch {
            logger.error("[Diag.Undo] meal log fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func deleteLinkedMealLog(of meal: PlannedMeal, in ctx: ModelContext) {
        guard let logID = meal.linkedMealLogID else {
            return
        }
        var descriptor = FetchDescriptor<MealLog>(predicate: #Predicate<MealLog> { $0.id == logID })
        descriptor.fetchLimit = 1
        if let log = fetchLog(descriptor, in: ctx) {
            ctx.delete(log)
        }
        meal.linkedMealLogID = nil
    }

    // MARK: - Shift later meals

    /// Persists shifted scheduled times for the meals after `eatenMealID`
    /// (pure math in `MealShiftPlanner`) and re-arms their reminders.
    private static func applyMealShift(eatenMealID: UUID, eatenAt: Date, env: Env) {
        let meals = todaysMeals(env)
        let results = MealShiftPlanner.computeShift(
            todaysMeals: meals,
            eatenMealID: eatenMealID,
            actualEatTime: eatenAt
        )
        guard !results.isEmpty else {
            return
        }
        let byID = Dictionary(results.map { ($0.mealID, $0) }, uniquingKeysWith: { first, _ in first })
        for meal in meals {
            guard let shift = byID[meal.id] else {
                continue
            }
            meal.scheduledTime = shift.newScheduledTime
            cancelReminders(forMealID: meal.id, notifications: env.notifications)
            if shift.newScheduledDate > Date(), let notifications = env.notifications {
                scheduleReminders(for: meal, at: shift.newScheduledDate, notifications: notifications)
            }
        }
    }

    // MARK: - Same-day rebalance

    /// Brings the day back to its target: reads eaten + remaining planned meals
    /// from the store (never a cached array), computes the residual with
    /// `MealRebalancer` and applies per-meal additive adjustments. No-op below
    /// the noise threshold or with nothing left to eat.
    static func applyMacroRebalance(env: Env) {
        let canonical = CanonicalMeals.meals(on: Date(), in: env.modelContext)
        let eaten = canonical.filter { $0.status == .eaten }
        let remaining = canonical.filter { $0.status == .planned }
        guard !remaining.isEmpty else {
            return
        }
        // The target sums plan baselines; freeze them before moving totals so
        // this rebalance can't feed back into the next one.
        for meal in canonical {
            meal.capturePlanBaselineIfNeeded()
        }
        let consumed = MealRebalancer.Macros(
            calories: eaten.reduce(0.0) { $0 + $1.totalCalories },
            protein: eaten.reduce(0.0) { $0 + $1.totalProtein },
            carbs: eaten.reduce(0.0) { $0 + $1.totalCarbs },
            fat: eaten.reduce(0.0) { $0 + $1.totalFat }
        )
        let planned = remaining.map {
            MealRebalancer.PlannedMealMacros(
                id: $0.id,
                calories: $0.totalCalories,
                protein: $0.totalProtein,
                carbs: $0.totalCarbs,
                fat: $0.totalFat
            )
        }
        let targets = DailyNutritionTargets.today(
            in: env.modelContext,
            whoopAvgTDEE: env.whoopAvgTDEE,
            recoveryScore: env.recoveryScore ?? DailyNutritionTargets.storedRecoveryScore(in: env.modelContext)
        )
        let adjustments = MealRebalancer.rebalance(
            dayTargets: MealRebalancer.Targets(
                calories: Double(targets.calories),
                protein: Double(targets.protein),
                carbs: Double(targets.carbs),
                fat: Double(targets.fat)
            ),
            consumed: consumed,
            remaining: planned
        )
        for adjustment in adjustments where !adjustment.isZero {
            guard let meal = remaining.first(where: { $0.id == adjustment.mealID }) else {
                continue
            }
            meal.totalCalories = max(0, meal.totalCalories + adjustment.calories)
            meal.totalProtein = max(0, meal.totalProtein + adjustment.protein)
            meal.totalCarbs = max(0, meal.totalCarbs + adjustment.carbs)
            meal.totalFat = max(0, meal.totalFat + adjustment.fat)
        }
    }
}
