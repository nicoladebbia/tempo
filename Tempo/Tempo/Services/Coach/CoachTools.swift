//
// CoachTools.swift
// Tempo
//
// Coach v2.1 Phase 3 — the 10 tools the agent can call.
//
// Each tool is a pure-Swift static method that mutates SwiftData via a
// passed-in ModelContext. No AI calls live here; the agent loop (Phase 6)
// dispatches by name. Tools are deliberately synchronous over the
// model-context to keep dispatch testable.
//
// Per .plans/coach-v2.1/03-services-and-data-flow.md and §04-ai-architecture.md
// (the tool reference table). Tool signatures match the Anthropic input
// schemas declared by the Coach agent loop.
//

import Foundation
import SwiftData

// MARK: - CoachToolError

enum CoachToolError: Error, Equatable {
    /// Tool received an ID that doesn't resolve in the current ModelContext.
    case mealNotFound(UUID)
    case preferenceNotFound(UUID)
    case planNotFound

    /// The meal is in a state that disallows this mutation.
    /// e.g., moving a meal that's already been eaten.
    case mealAlreadyLogged(UUID)
    case mealAlreadySkipped(UUID)

    /// Tool input failed validation.
    case invalidTimeFormat(String)
    case invalidActivityWindow(startMin: Int, endMin: Int)
    case invalidMaxPrepMinutes(Int)
}

// MARK: - ToolOutput

/// Common return shape for every tool. `summary` is a human-readable
/// confirmation line the chat UI renders ("Moved dinner 19:30 → 20:30").
/// `sideEffects` lists any extra mutations the agent should mention to the
/// user. `pendingQuestion` is set ONLY by the `askUser` tool — it signals
/// the chat UI to render a question bubble with optional choice chips.
struct ToolOutput: Equatable {
    let summary: String
    let sideEffects: [String]
    let pendingQuestion: PendingQuestion?

    init(
        summary: String,
        sideEffects: [String] = [],
        pendingQuestion: PendingQuestion? = nil
    ) {
        self.summary = summary
        self.sideEffects = sideEffects
        self.pendingQuestion = pendingQuestion
    }
}

// MARK: - PendingQuestion

/// Emitted by the `askUser` tool. The chat UI renders this as a question
/// bubble. `choices` (when non-empty) become tappable chips; nil/empty
/// means free-text reply.
struct PendingQuestion: Equatable {
    let question: String
    let choices: [String]
}

// MARK: - Activity placement

enum ActivityImpact: Equatable {
    case shiftsMealsOnly
    case changesDayType(DayType)
}

enum MealPlacement: Equatable {
    case beforeActivity(bufferMin: Int)
    case afterActivity(bufferMin: Int)
}

// MARK: - Notifications

/// Notification side-effect protocol so tools stay pure-Swift and testable.
/// The real implementation lives in Phase 6 wiring (UNUserNotificationCenter
/// bridge). Tests inject a no-op stub.
protocol CoachMealNotificationScheduler {
    func cancelMealNotification(mealID: UUID)
    func scheduleMealNotification(mealID: UUID, fireAt: Date)
}

/// No-op default. Used in tests and as the placeholder until Phase 6
/// wires a real bridge.
struct NoopCoachMealNotificationScheduler: CoachMealNotificationScheduler {
    func cancelMealNotification(mealID _: UUID) {}
    func scheduleMealNotification(mealID _: UUID, fireAt _: Date) {}
}

// MARK: - CoachToolHelpers

enum CoachToolHelpers {
    /// Parses "HH:mm" (24h) into (hour, minute). Throws on bad input.
    static func parseHHmm(_ raw: String) throws -> (hour: Int, minute: Int) {
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0...23).contains(h),
              (0...59).contains(m)
        else {
            throw CoachToolError.invalidTimeFormat(raw)
        }
        return (h, m)
    }

    /// Combines a calendar day with an HH:mm string into a Date in the
    /// supplied calendar. Used by moveMeal and shiftBedtime.
    static func date(
        forDay day: Date,
        hhmm: String,
        calendar: Calendar = .current
    ) throws -> Date {
        let (h, m) = try parseHHmm(hhmm)
        let dayStart = calendar.startOfDay(for: day)
        guard let result = calendar.date(bySettingHour: h, minute: m, second: 0, of: dayStart) else {
            throw CoachToolError.invalidTimeFormat(hhmm)
        }
        return result
    }

    /// Fetches a PlannedMeal by id. Throws .mealNotFound when absent.
    static func plannedMeal(id: UUID, in context: ModelContext) throws -> PlannedMeal {
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { $0.id == id }
        )
        guard let meal = try context.fetch(descriptor).first else {
            throw CoachToolError.mealNotFound(id)
        }
        return meal
    }

    /// Fetches a LearnedPreference by id. Throws .preferenceNotFound.
    static func preference(id: UUID, in context: ModelContext) throws -> LearnedPreference {
        let descriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { $0.id == id }
        )
        guard let pref = try context.fetch(descriptor).first else {
            throw CoachToolError.preferenceNotFound(id)
        }
        return pref
    }

    /// Fetches the active WeeklyMealPlan. Throws .planNotFound when no
    /// active plan exists.
    static func activeWeeklyPlan(in context: ModelContext) throws -> WeeklyMealPlan {
        let descriptor = FetchDescriptor<WeeklyMealPlan>(
            predicate: #Predicate<WeeklyMealPlan> { $0.isActive }
        )
        guard let plan = try context.fetch(descriptor).first else {
            throw CoachToolError.planNotFound
        }
        return plan
    }
}

// MARK: - CoachTools

/// Dispatch surface for the agent. Each method is a self-contained
/// tool — input args → ToolOutput. The agent loop (Phase 6) calls these
/// after parsing tool_use blocks from Anthropic.
enum CoachTools {
    // MARK: moveMeal

    /// Shift a planned meal's scheduledTime to `newTimeHHmm`. Reschedules
    /// notifications. Refuses when the meal has been eaten or skipped.
    @MainActor
    static func moveMeal(
        mealID: UUID,
        newTimeHHmm: String,
        notifications: CoachMealNotificationScheduler = NoopCoachMealNotificationScheduler(),
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> ToolOutput {
        let meal = try CoachToolHelpers.plannedMeal(id: mealID, in: context)
        guard meal.status != .eaten else {
            throw CoachToolError.mealAlreadyLogged(mealID)
        }
        guard meal.status != .skipped else {
            throw CoachToolError.mealAlreadySkipped(mealID)
        }
        // Validates HH:mm; we also use the resulting Date for the notification.
        let newDate = try CoachToolHelpers.date(forDay: meal.dayDate, hhmm: newTimeHHmm, calendar: calendar)

        let originalTime = meal.scheduledTime
        meal.scheduledTime = formattedHHmm(from: newDate, calendar: calendar)
        if meal.status == .planned {
            meal.status = .modified
        }
        try context.save()

        notifications.cancelMealNotification(mealID: mealID)
        notifications.scheduleMealNotification(mealID: mealID, fireAt: newDate)

        return ToolOutput(
            summary: "Moved \(meal.mealName) \(originalTime) → \(meal.scheduledTime)"
        )
    }

    // MARK: swapDayType

    /// Swap one calendar day's training type and (optionally) scale every
    /// meal's macros by a caloriesMultiplier ratio.
    ///
    /// `caloriesMultiplier` is the ratio `newTarget.calories / oldTarget.calories`
    /// — computed by the caller (typically from TDEECalculator output).
    /// Macros scale by the same ratio when `scaleMacros == true`.
    /// Pass 1.0 (or `scaleMacros: false`) to leave macros alone.
    @MainActor
    static func swapDayType(
        date: Date,
        newType: DayType,
        scaleMacros: Bool,
        caloriesMultiplier: Double,
        context: ModelContext,
        calendar: Calendar = .current
    ) throws -> ToolOutput {
        let plan = try CoachToolHelpers.activeWeeklyPlan(in: context)
        let weekdayIndex = calendar.component(.weekday, from: date) // 1=Sunday … 7=Saturday
        // dayTypeAssignments is keyed by mealNumber-day-index per existing schema:
        // 0 = Monday, 6 = Sunday (per MealPlanPrompts/weeklyPlanPrompt rules).
        let dayIndex0Mon = ((weekdayIndex + 5) % 7) // Sunday(1)→6, Monday(2)→0, …
        let currentRaw = plan.dayTypeAssignments[dayIndex0Mon] ?? DayType.rest.rawValue
        let currentType = DayType(rawValue: currentRaw) ?? .rest
        guard currentType != newType else {
            return ToolOutput(summary: "Already \(newType.displayName) on this day — no change.")
        }
        var assignments = plan.dayTypeAssignments
        assignments[dayIndex0Mon] = newType.rawValue
        plan.dayTypeAssignments = assignments

        var sideEffects: [String] = []
        if scaleMacros, abs(caloriesMultiplier - 1.0) > 0.001 {
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let descriptor = FetchDescriptor<PlannedMeal>(
                predicate: #Predicate<PlannedMeal> { meal in
                    meal.dayDate >= dayStart && meal.dayDate < dayEnd
                }
            )
            let meals = (try? context.fetch(descriptor)) ?? []
            for meal in meals where meal.status == .planned || meal.status == .modified {
                meal.totalCalories *= caloriesMultiplier
                meal.totalProtein *= caloriesMultiplier
                meal.totalCarbs *= caloriesMultiplier
                meal.totalFat *= caloriesMultiplier
            }
            if !meals.isEmpty {
                let pct = Int(((caloriesMultiplier - 1.0) * 100).rounded())
                let sign = pct >= 0 ? "+" : ""
                sideEffects.append("Scaled \(meals.count) meal\(meals.count == 1 ? "" : "s") by \(sign)\(pct)% kcal")
            }
        }
        try context.save()

        return ToolOutput(
            summary: "Day type: \(currentType.displayName) → \(newType.displayName)",
            sideEffects: sideEffects
        )
    }

    // MARK: insertActivity

    /// Composite: optionally change the day's type (if dayImpact says so)
    /// and shift one meal relative to the activity window.
    /// `nearestMealNumber` is the mealNumber (1=Bf, 2=Lu, 3=Di, 4=Sn) the
    /// shift applies to. `mealPlacement` controls whether the meal lands
    /// before or after the activity, with a buffer.
    @MainActor
    static func insertActivity(
        name: String,
        date: Date,
        startMin: Int,
        endMin: Int,
        dayImpact: ActivityImpact,
        nearestMealNumber: Int,
        mealPlacement: MealPlacement,
        notifications: CoachMealNotificationScheduler = NoopCoachMealNotificationScheduler(),
        context: ModelContext,
        calendar: Calendar = .current,
        dayTypeCaloriesMultiplier: Double = 1.0
    ) throws -> ToolOutput {
        guard startMin >= 0, endMin > startMin, endMin <= 24 * 60 else {
            throw CoachToolError.invalidActivityWindow(startMin: startMin, endMin: endMin)
        }

        var sideEffects: [String] = []

        // Day-type swap (if needed). Errors propagate.
        if case let .changesDayType(newType) = dayImpact {
            let swapResult = try swapDayType(
                date: date,
                newType: newType,
                scaleMacros: abs(dayTypeCaloriesMultiplier - 1.0) > 0.001,
                caloriesMultiplier: dayTypeCaloriesMultiplier,
                context: context,
                calendar: calendar
            )
            sideEffects.append(swapResult.summary)
            sideEffects.append(contentsOf: swapResult.sideEffects)
        }

        // Locate the target meal by date + mealNumber.
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= dayStart
                    && meal.dayDate < dayEnd
                    && meal.mealNumber == nearestMealNumber
            }
        )
        guard let meal = try context.fetch(descriptor).first else {
            return ToolOutput(
                summary: "Inserted activity '\(name)' \(formatRange(startMin: startMin, endMin: endMin))",
                sideEffects: sideEffects + ["No meal \(nearestMealNumber) found on this day — left meals as-is."]
            )
        }
        guard meal.status != .eaten, meal.status != .skipped else {
            return ToolOutput(
                summary: "Inserted activity '\(name)' \(formatRange(startMin: startMin, endMin: endMin))",
                sideEffects: sideEffects + ["Meal \(nearestMealNumber) is already \(meal.status.rawValue); not moved."]
            )
        }

        // Compute the new meal time around the activity window.
        let targetMinute: Int
        switch mealPlacement {
        case let .beforeActivity(buffer):
            targetMinute = max(0, startMin - buffer)
        case let .afterActivity(buffer):
            targetMinute = min(24 * 60 - 1, endMin + buffer)
        }
        let h = targetMinute / 60
        let m = targetMinute % 60
        let newHHmm = String(format: "%02d:%02d", h, m)
        let moveResult = try moveMeal(
            mealID: meal.id,
            newTimeHHmm: newHHmm,
            notifications: notifications,
            context: context,
            calendar: calendar
        )

        return ToolOutput(
            summary: "Inserted '\(name)' \(formatRange(startMin: startMin, endMin: endMin))",
            sideEffects: sideEffects + [moveResult.summary]
        )
    }

    // MARK: skipMeal

    /// Mark a planned meal as skipped. Cancels its notification. Refuses
    /// if already eaten. Redistribution is the agent's separate step.
    @MainActor
    static func skipMeal(
        mealID: UUID,
        notifications: CoachMealNotificationScheduler = NoopCoachMealNotificationScheduler(),
        context: ModelContext
    ) throws -> ToolOutput {
        let meal = try CoachToolHelpers.plannedMeal(id: mealID, in: context)
        guard meal.status != .eaten else {
            throw CoachToolError.mealAlreadyLogged(mealID)
        }
        meal.status = .skipped
        try context.save()
        notifications.cancelMealNotification(mealID: mealID)
        return ToolOutput(summary: "Skipped \(meal.mealName)")
    }

    // MARK: swapToQuickerMeal

    /// Returns the top-3 quicker Recipe alternatives whose totalMinutes
    /// fits under maxPrepMin and macros land closest to the original
    /// meal's macros. Does NOT auto-replace — agent presents these to
    /// the user.
    @MainActor
    static func swapToQuickerMeal(
        mealID: UUID,
        maxPrepMin: Int,
        context: ModelContext
    ) throws -> ToolOutput {
        guard maxPrepMin > 0 else {
            throw CoachToolError.invalidMaxPrepMinutes(maxPrepMin)
        }
        let meal = try CoachToolHelpers.plannedMeal(id: mealID, in: context)

        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { recipe in
                !recipe.isArchived
            }
        )
        let candidates = (try? context.fetch(descriptor)) ?? []
        let filtered = candidates.filter { $0.totalMinutes > 0 && $0.totalMinutes <= maxPrepMin }
        guard !filtered.isEmpty else {
            return ToolOutput(
                summary: "No recipes ≤\(maxPrepMin) min in your library yet.",
                sideEffects: []
            )
        }

        // Rank by macro distance to the meal's totals.
        let ranked = filtered
            .map { recipe -> (Recipe, Double) in
                let dCal = abs(recipe.totalCalories - meal.totalCalories)
                let dP = abs(recipe.totalProteinGrams - meal.totalProtein) * 4 // kcal-equiv weighting
                let dC = abs(recipe.totalCarbsGrams - meal.totalCarbs) * 4
                let dF = abs(recipe.totalFatGrams - meal.totalFat) * 9
                return (recipe, dCal + dP + dC + dF)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(3)

        let lines = ranked.map { recipe, _ in
            "• \(recipe.name) — \(recipe.totalMinutes) min, \(Int(recipe.totalCalories)) kcal"
        }
        return ToolOutput(
            summary: "Top \(lines.count) quicker option\(lines.count == 1 ? "" : "s") for \(meal.mealName):",
            sideEffects: lines
        )
    }

    // MARK: shiftBedtime

    /// v1 of this tool: acknowledgement only (no DB persistence).
    /// Validates the HH:mm format and returns a confirmation. Future
    /// versions persist a BedtimeOverride row per the v2.1 plan §"What
    /// did NOT make it into v2".
    static func shiftBedtime(
        date: Date,
        newBedtimeHHmm: String,
        calendar: Calendar = .current
    ) throws -> ToolOutput {
        _ = try CoachToolHelpers.date(forDay: date, hhmm: newBedtimeHHmm, calendar: calendar)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return ToolOutput(
            summary: "Bedtime shift acknowledged: \(formatter.string(from: date)) at \(newBedtimeHHmm)",
            sideEffects: ["(this-session-only — no notification changes yet)"]
        )
    }

    // MARK: askUser

    /// No-op mutation. Emits a PendingQuestion the chat UI renders as a
    /// question bubble. Optional `choices` becomes tappable chips.
    static func askUser(
        question: String,
        choices: [String] = []
    ) -> ToolOutput {
        ToolOutput(
            summary: question,
            sideEffects: [],
            pendingQuestion: PendingQuestion(question: question, choices: choices)
        )
    }

    // MARK: updatePreference

    enum UpdateAction: String, Codable {
        /// Mark this preference as superseded by a new one (caller supplies newID).
        case supersede
        /// Same content, but keep with explicit scope. Used by the agent when
        /// a previously-broad preference needs to be narrowed (e.g., "this
        /// applies on weekdays only").
        case keepClarifyScope
        /// Soft delete.
        case deactivate
        /// Flag this as a one-off — confidence stays where it is but the
        /// agent should treat it as not-recurring for ranking.
        case markOneOff
    }

    @MainActor
    static func updatePreference(
        prefID: UUID,
        action: UpdateAction,
        newText: String? = nil,
        newScope: LearnedPreference.Scope? = nil,
        supersededByID: UUID? = nil,
        context: ModelContext
    ) throws -> ToolOutput {
        let pref = try CoachToolHelpers.preference(id: prefID, in: context)

        switch action {
        case .supersede:
            guard let supersededByID else {
                // Without a replacement ID, treat as a deactivate to avoid leaving
                // an orphan supersession marker.
                pref.deactivate()
                try context.save()
                return ToolOutput(summary: "Deactivated preference (no replacement supplied).")
            }
            pref.supersede(by: supersededByID)
        case .keepClarifyScope:
            if let newScope { pref.scope = newScope }
            if let newText { pref.text = newText }
            pref.needsReview = false
        case .deactivate:
            pref.deactivate()
        case .markOneOff:
            // A "one-off" tag in v1 just clears the review flag and bumps
            // the source down to inferred so the retriever weighs it lower.
            // We don't store an explicit one-off flag yet.
            pref.needsReview = false
            if pref.source == .explicit || pref.source == .observed {
                pref.source = .inferred
            }
        }
        try context.save()

        return ToolOutput(summary: "Preference updated (\(action.rawValue))")
    }

    // MARK: recordPreference

    /// Insert a new LearnedPreference with source=.explicit by default.
    /// The extractor (Phase 4) uses this for chat-derived prefs;
    /// askUser confirmations use it too.
    @MainActor
    static func recordPreference(
        text: String,
        subject: String,
        source: LearnedPreference.Source = .explicit,
        polarity: LearnedPreference.Polarity = .positive,
        scope: LearnedPreference.Scope = .always,
        confidence: Double? = nil,
        conversationID: UUID? = nil,
        turnIndex: Int? = nil,
        context: ModelContext
    ) throws -> ToolOutput {
        let pref = LearnedPreference(
            text: text,
            subject: subject,
            source: source,
            polarity: polarity,
            scope: scope,
            confidence: confidence,
            evidenceConvId: conversationID,
            evidenceTurnIndex: turnIndex
        )
        context.insert(pref)
        try context.save()
        return ToolOutput(summary: "Saved preference: \(text)")
    }

    // MARK: - Private helpers

    private static func formattedHHmm(from date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    private static func formatRange(startMin: Int, endMin: Int) -> String {
        let sH = startMin / 60, sM = startMin % 60
        let eH = endMin / 60, eM = endMin % 60
        return String(format: "%02d:%02d–%02d:%02d", sH, sM, eH, eM)
    }
}
