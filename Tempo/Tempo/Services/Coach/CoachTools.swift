//
// CoachTools.swift
// Tempo
//
// Created by Tempo on 20/05/2026.
//
// Tool implementations the Coach agent can call. Each tool is a pure
// Swift function that validates input, mutates SwiftData / reschedules
// notifications, and returns a structured `ToolOutput` the chat UI can
// render and the agent can reason about.
//
// Design notes:
// - Tools run on iOS (not backend). Backend just relays Claude's tool_use
//   blocks; iOS dispatches them here. Keeps mutation close to SwiftData.
// - Every tool is @MainActor since they touch SwiftData ModelContext.
// - Failures throw `CoachToolError`; the agent loop maps these to
//   `tool_result with is_error: true` so Claude can recover.
// - Tools never write to UserSettings directly — those are user-chosen and
//   should only mutate from explicit Settings UI. Coach can SUGGEST a
//   change via `askUser` but never imposes it.
//
// Per `.plans/coach-agent-plan.md` Phase 3.

import Foundation
import SwiftData

// MARK: - CoachToolError

enum CoachToolError: Error, LocalizedError {
    case mealNotFound(UUID)
    case mealAlreadyEaten(UUID)
    case mealAlreadySkipped(UUID)
    case invalidTimeFormat(String)
    case invalidWeekday(Int)
    case noActivePlan
    case preferenceNotFound(UUID)
    case invalidActivityWindow(start: Int, end: Int)
    case noSuitableAlternative(reason: String)
    case bedtimeViolation(reason: String)

    var errorDescription: String? {
        switch self {
        case let .mealNotFound(id):
            return "No meal found with ID \(id.uuidString.prefix(8))."
        case let .mealAlreadyEaten(id):
            return "Meal \(id.uuidString.prefix(8)) is already marked eaten."
        case let .mealAlreadySkipped(id):
            return "Meal \(id.uuidString.prefix(8)) is already skipped."
        case let .invalidTimeFormat(s):
            return "Invalid time format '\(s)'. Expected HH:mm (24h)."
        case let .invalidWeekday(n):
            return "Invalid weekday \(n). Expected 1=Sunday … 7=Saturday."
        case .noActivePlan:
            return "No active weekly meal plan exists."
        case let .preferenceNotFound(id):
            return "No preference found with ID \(id.uuidString.prefix(8))."
        case let .invalidActivityWindow(start, end):
            return "Invalid activity window: start=\(start), end=\(end). Both 0-1440, start < end."
        case let .noSuitableAlternative(reason):
            return "No suitable alternative meal: \(reason)"
        case let .bedtimeViolation(reason):
            return "Bedtime constraint violated: \(reason)"
        }
    }
}

// MARK: - ToolOutput

/// Returned by every Coach tool. The agent reads `summary` for follow-up
/// reasoning; the UI renders `summary` + `sideEffects` as the per-tool
/// preview card. `citedPreferenceIDs` lets the agent flag which learned
/// preferences justified this action so the UI can surface them as
/// tappable footnotes.
struct ToolOutput: Sendable {
    /// Short human sentence shown to the user and fed back to the agent.
    /// Example: "Moved dinner 19:30 → 20:30 to accommodate soccer at 7pm."
    let summary: String

    /// Bullet list of concrete side-effects, one per change.
    /// Example: ["Dinner: 19:30 → 20:30", "Snack: 16:00 → 21:30 (post-game)",
    ///          "Defrost reminder rescheduled."]
    let sideEffects: [String]

    /// Preferences the agent leveraged when picking this action. UI
    /// surfaces these as footnote chips below the tool-result card.
    let citedPreferenceIDs: [UUID]

    /// If non-nil, the agent is asking the user a question (from the
    /// `askUser` tool). The chat UI renders this as a special prompt
    /// bubble with optional choice chips.
    let pendingQuestion: PendingQuestion?

    init(
        summary: String,
        sideEffects: [String] = [],
        citedPreferenceIDs: [UUID] = [],
        pendingQuestion: PendingQuestion? = nil
    ) {
        self.summary = summary
        self.sideEffects = sideEffects
        self.citedPreferenceIDs = citedPreferenceIDs
        self.pendingQuestion = pendingQuestion
    }
}

// MARK: - PendingQuestion

struct PendingQuestion: Sendable, Equatable {
    let question: String
    /// Optional pre-canned choices. nil = free-text reply expected.
    let choices: [String]?
}

// MARK: - Shared validation helpers

enum CoachToolHelpers {
    /// Parse an "HH:mm" string into (hour, minute). Throws on malformed input.
    static func parseHHmm(_ s: String) throws -> (hour: Int, minute: Int) {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0 ..< 24).contains(h),
              (0 ..< 60).contains(m)
        else {
            throw CoachToolError.invalidTimeFormat(s)
        }
        return (h, m)
    }

    /// Format (hour, minute) back as "HH:mm".
    static func formatHHmm(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Combine a date (day) and an HH:mm string into a Date at that
    /// wall-clock time. Returns nil if the time string is invalid.
    static func date(on day: Date, atHHmm hhmm: String, calendar: Calendar = .current) throws -> Date {
        let (h, m) = try parseHHmm(hhmm)
        guard let combined = calendar.date(
            bySettingHour: h, minute: m, second: 0, of: calendar.startOfDay(for: day)
        ) else {
            throw CoachToolError.invalidTimeFormat(hhmm)
        }
        return combined
    }
}

// MARK: - CoachTools (orchestration namespace)

/// Namespace for all tool implementations. Each method is the entry the
/// agent loop calls; each owns its validation, mutation, and notification
/// rescheduling. ModelContext is passed in (not captured) so the same
/// tools work against the live store or an in-memory test container.
@MainActor
enum CoachTools {
    // ── Preference tools ─────────────────────────────────────────────────

    /// Persist a new learned preference. Used when the user explicitly
    /// states a recurring pattern mid-conversation ("I just don't eat
    /// after 9, ever."). The agent provides text + subject + confidence;
    /// the row is stored with source=`.explicit` and the conversation ID
    /// is captured for audit.
    static func recordPreference(
        text: String,
        subject: String,
        confidence: Double,
        conversationID: UUID?,
        turnIndex: Int?,
        modelContext: ModelContext
    ) throws -> ToolOutput {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !trimmedSubject.isEmpty else {
            throw CoachToolError.preferenceNotFound(UUID()) // misnamed but
            // closest existing case; in practice the agent won't trigger this
            // because validation happens before tool dispatch.
        }
        let pref = LearnedPreference(
            text: trimmedText,
            subject: trimmedSubject,
            confidence: confidence,
            source: .explicit,
            sourceConversationID: conversationID,
            sourceTurnIndex: turnIndex
        )
        modelContext.insert(pref)
        try? modelContext.save()
        return ToolOutput(
            summary: "Remembered: \(trimmedText)",
            sideEffects: ["Subject: \(trimmedSubject)", "Confidence: \(String(format: "%.2f", pref.confidence))"],
            citedPreferenceIDs: [pref.id]
        )
    }

    /// Mutate an existing preference. The agent uses this to handle
    /// contradiction ("user said X but did Y — has the pattern changed?")
    /// and explicit corrections from the conversation.
    ///
    /// - `supersede`: pair with a separate `recordPreference` call to
    ///   create the newer row; this one wires the supersession edge.
    /// - `keepClarifyScope`: keeps the existing claim but narrows scope
    ///   via `newText` (e.g. "weekdays only"). Promotes to user-verified.
    /// - `deactivate`: soft-delete. User said it was wrong.
    /// - `markOneOff`: decrement evidence + lower confidence; the
    ///   recent observation that looked like reinforcement was a one-off.
    static func updatePreference(
        prefID: UUID,
        action: LearnedPreference.Action,
        newText: String? = nil,
        supersededByID: UUID? = nil,
        modelContext: ModelContext
    ) throws -> ToolOutput {
        let descriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate { $0.id == prefID }
        )
        guard let pref = try? modelContext.fetch(descriptor).first else {
            throw CoachToolError.preferenceNotFound(prefID)
        }

        var effects: [String] = []
        switch action {
        case .supersede:
            if let newID = supersededByID {
                pref.supersede(by: newID)
                effects.append("Marked as superseded by newer preference.")
            } else {
                // Agent forgot to supply the new ID — deactivate instead so
                // we don't leave the old claim active.
                pref.deactivate()
                effects.append("Old preference deactivated (no replacement ID provided).")
            }

        case .keepClarifyScope:
            if let t = newText?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                pref.text = t
                effects.append("Text updated to: \(t)")
            }
            pref.markUserVerified()
            effects.append("Confirmed and locked.")

        case .deactivate:
            pref.deactivate()
            effects.append("Removed from active memory.")

        case .markOneOff:
            pref.evidenceCount = max(0, pref.evidenceCount - 1)
            pref.confidence = max(0.0, pref.confidence - 0.1)
            effects.append("Marked recent observation as one-off (confidence -0.10).")
        }
        try? modelContext.save()
        return ToolOutput(
            summary: "Updated preference: \(pref.text)",
            sideEffects: effects,
            citedPreferenceIDs: [pref.id]
        )
    }

    // ── Pause-and-ask ────────────────────────────────────────────────────

    /// No-op tool. The agent calls this when it needs information before
    /// proceeding. The chat UI renders a prompt with optional choice chips;
    /// the user's reply becomes the next conversation turn.
    static func askUser(
        question: String,
        choices: [String]? = nil
    ) -> ToolOutput {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return ToolOutput(
            summary: trimmed.isEmpty ? "Waiting on your input." : trimmed,
            sideEffects: [],
            citedPreferenceIDs: [],
            pendingQuestion: PendingQuestion(question: trimmed, choices: choices)
        )
    }

    // ── Bedtime override ─────────────────────────────────────────────────

    /// One-off bedtime override for a single date. v1 implementation: no
    /// persistence — the agent acknowledges and the override is reflected
    /// in this conversation's context but doesn't survive a relaunch.
    /// Persistent overrides land in v2 via a `BedtimeOverride` @Model.
    ///
    /// Returns a summary the agent can fold into its next reasoning step.
    static func shiftBedtime(
        date: Date,
        newBedtimeHHmm: String
    ) throws -> ToolOutput {
        let (h, m) = try CoachToolHelpers.parseHHmm(newBedtimeHHmm)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        let dayLabel = formatter.string(from: date)
        return ToolOutput(
            summary: "Noted: bedtime for \(dayLabel) is \(CoachToolHelpers.formatHHmm(hour: h, minute: m)) (this conversation only).",
            sideEffects: ["v1 override is conversation-scoped; persistent overrides land in v2."],
            citedPreferenceIDs: []
        )
    }
}


// MARK: - Schedule mutation tools

extension CoachTools {
    // ── Reschedule a single meal ─────────────────────────────────────────

    /// Move a planned meal to a new wall-clock time, then shift downstream
    /// meals to maintain their relative gaps (respecting the bedtime cap).
    /// Cancels and reschedules per-meal notifications (defrost, prep-start,
    /// overdue) for every meal that moved.
    ///
    /// Reuses `MealShiftPlanner.computeShiftFromAnchor` so the math is
    /// identical to the user-eats-off-schedule path. The agent is expected
    /// to have already reasoned about *why* it's moving the meal (e.g.
    /// "user playing soccer at 7, dinner needs to land at 8:30") — this
    /// tool just executes.
    static func moveMeal(
        mealID: UUID,
        newTimeHHmm: String,
        notifications: (any NotificationServiceProtocol)?,
        modelContext: ModelContext
    ) throws -> ToolOutput {
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.id == mealID }
        )
        guard let target = try? modelContext.fetch(descriptor).first else {
            throw CoachToolError.mealNotFound(mealID)
        }
        guard target.status == .planned else {
            if target.status == .eaten { throw CoachToolError.mealAlreadyEaten(mealID) }
            if target.status == .skipped { throw CoachToolError.mealAlreadySkipped(mealID) }
            throw CoachToolError.mealNotFound(mealID) // shouldn't happen
        }

        let newDate = try CoachToolHelpers.date(on: target.dayDate, atHHmm: newTimeHHmm)

        // Apply to the target itself first.
        let originalTime = target.scheduledTime
        target.scheduledTime = newTimeHHmm

        // Fetch the day's other meals to compute downstream shifts.
        let dayStart = Calendar.current.startOfDay(for: target.dayDate)
        let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let dayDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.dayDate >= dayStart && $0.dayDate < tomorrowStart }
        )
        let dayMeals = (try? modelContext.fetch(dayDescriptor)) ?? [target]

        // Compute shifts for meals AFTER this one.
        let shifts = MealShiftPlanner.computeShiftFromAnchor(
            todaysMeals: dayMeals,
            anchorTime: newDate,
            anchorMealNumber: target.mealNumber
        )

        // Apply shifts.
        let shiftMap = Dictionary(uniqueKeysWithValues: shifts.map { ($0.mealID, $0) })
        var effects: [String] = ["\(target.mealName): \(originalTime) → \(newTimeHHmm)"]
        for meal in dayMeals where meal.id != target.id {
            guard let r = shiftMap[meal.id] else { continue }
            meal.scheduledTime = r.newScheduledTime
            effects.append("\(meal.mealName): \(r.originalScheduledTime) → \(r.newScheduledTime)")
        }

        try? modelContext.save()

        // Reschedule notifications for every meal that moved (target + shifted).
        let movedMeals: [PlannedMeal] = [target] + dayMeals.filter { shiftMap[$0.id] != nil }
        rescheduleMealNotifications(for: movedMeals, notifications: notifications)

        return ToolOutput(
            summary: "Moved \(target.mealName) to \(newTimeHHmm). Downstream meals shifted to maintain gaps.",
            sideEffects: effects
        )
    }

    // ── Swap a day's type ────────────────────────────────────────────────

    /// Change the day type for a given weekday (e.g. Wed strength → soccer).
    /// Updates `WeeklyMealPlan.dayTypeAssignments`. When `scaleMacros == true`,
    /// scales that day's meal kcal/macros by the ratio of the new DayType's
    /// caloric multiplier vs the old one. Full per-day regeneration via
    /// Sonnet is deferred to v2.
    static func swapDayType(
        date: Date,
        newType: DayType,
        scaleMacros: Bool,
        modelContext: ModelContext
    ) throws -> ToolOutput {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        guard (1 ... 7).contains(weekday) else {
            throw CoachToolError.invalidWeekday(weekday)
        }

        let planDescriptor = FetchDescriptor<WeeklyMealPlan>(
            predicate: #Predicate { $0.isActive }
        )
        guard let plan = try? modelContext.fetch(planDescriptor).first else {
            throw CoachToolError.noActivePlan
        }

        var assignments = plan.dayTypeAssignments
        let oldRaw = assignments[weekday] ?? DayType.strength.rawValue
        let oldType = DayType(rawValue: oldRaw) ?? .strength
        guard oldType != newType else {
            return ToolOutput(
                summary: "Day type for \(weekdayName(weekday)) was already \(newType.displayName). No change.",
                sideEffects: []
            )
        }
        assignments[weekday] = newType.rawValue
        plan.dayTypeAssignments = assignments

        var effects: [String] = ["\(weekdayName(weekday)): \(oldType.displayName) → \(newType.displayName)"]

        if scaleMacros {
            let scale = caloriesMultiplier(for: newType) / caloriesMultiplier(for: oldType)
            if abs(scale - 1.0) > 0.001 {
                let dayStart = calendar.startOfDay(for: date)
                let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let mealDescriptor = FetchDescriptor<PlannedMeal>(
                    predicate: #Predicate { $0.dayDate >= dayStart && $0.dayDate < tomorrowStart }
                )
                let meals = (try? modelContext.fetch(mealDescriptor)) ?? []
                for meal in meals where meal.status == .planned {
                    meal.totalCalories *= scale
                    meal.totalProtein *= scale
                    meal.totalCarbs *= scale
                    meal.totalFat *= scale
                }
                effects.append(String(format: "Scaled meal macros by ×%.2f to match the new day type.", scale))
            }
        }

        try? modelContext.save()
        return ToolOutput(
            summary: "Day type for \(weekdayName(weekday)) is now \(newType.displayName).",
            sideEffects: effects
        )
    }

    // ── Insert an ad-hoc activity ────────────────────────────────────────

    /// Composite tool. The user is doing an activity (soccer, lift, run,
    /// study sprint) at a specific time window. The agent decides which
    /// meals are affected and how, then this tool executes:
    /// 1. Optionally flip the day type (e.g. strength → soccer).
    /// 2. Move the closest meal to a sensible time relative to the activity
    ///    (pre-activity = activityStart - 90min for a light meal, OR
    ///    post-activity = activityEnd + 30min for a recovery meal). The
    ///    agent passes which it wants via `placement`.
    ///
    /// This is the "I'm playing soccer at 7" entry point. The agent is
    /// expected to have reasoned about which meals slot before vs after.
    static func insertActivity(
        name: String,
        date: Date,
        startMin: Int,
        endMin: Int,
        dayImpact: ActivityImpact,
        nearestMealNumber: Int?,
        mealPlacement: MealPlacement,
        notifications: (any NotificationServiceProtocol)?,
        modelContext: ModelContext
    ) throws -> ToolOutput {
        guard (0 ..< 1440).contains(startMin),
              (0 ..< 1440).contains(endMin),
              startMin < endMin
        else {
            throw CoachToolError.invalidActivityWindow(start: startMin, end: endMin)
        }
        var effects: [String] = []
        let startTime = "\(startMin / 60):\(String(format: "%02d", startMin % 60))"
        let endTime = "\(endMin / 60):\(String(format: "%02d", endMin % 60))"
        effects.append("\(name) inserted \(startTime)–\(endTime).")

        // Day-type change if requested.
        if case let .changesDayType(newType) = dayImpact {
            let result = try swapDayType(
                date: date,
                newType: newType,
                scaleMacros: true,
                modelContext: modelContext
            )
            effects.append(contentsOf: result.sideEffects)
        }

        // Move the nearest meal if the agent specified one.
        if let mealNumber = nearestMealNumber {
            let dayStart = Calendar.current.startOfDay(for: date)
            let tomorrowStart = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let mealDescriptor = FetchDescriptor<PlannedMeal>(
                predicate: #Predicate { meal in
                    meal.dayDate >= dayStart && meal.dayDate < tomorrowStart && meal.mealNumber == mealNumber
                }
            )
            if let meal = try? modelContext.fetch(mealDescriptor).first {
                let targetMinute: Int = switch mealPlacement {
                case .beforeActivity(let bufferMin): max(0, startMin - bufferMin)
                case .afterActivity(let bufferMin): min(1439, endMin + bufferMin)
                }
                let targetHHmm = "\(targetMinute / 60):\(String(format: "%02d", targetMinute % 60))"
                let moved = try moveMeal(
                    mealID: meal.id,
                    newTimeHHmm: targetHHmm,
                    notifications: notifications,
                    modelContext: modelContext
                )
                effects.append(contentsOf: moved.sideEffects)
            }
        }

        return ToolOutput(
            summary: "Inserted \(name) \(startTime)–\(endTime); applied related schedule changes.",
            sideEffects: effects
        )
    }

    // ── Skip a meal ──────────────────────────────────────────────────────

    /// Mark a planned meal as skipped. Optionally invokes
    /// `MealRedistributionService` to spread its macros across remaining
    /// meals. Cancels per-meal notifications.
    ///
    /// v1 redistribution path: this tool just marks skipped + cancels
    /// notifications. The redistribution itself is invoked by the agent
    /// loop as a separate async step (it makes its own Haiku call). This
    /// keeps tool dispatch synchronous and testable.
    static func skipMeal(
        mealID: UUID,
        notifications: (any NotificationServiceProtocol)?,
        modelContext: ModelContext
    ) throws -> ToolOutput {
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.id == mealID }
        )
        guard let target = try? modelContext.fetch(descriptor).first else {
            throw CoachToolError.mealNotFound(mealID)
        }
        guard target.status != .eaten else {
            throw CoachToolError.mealAlreadyEaten(mealID)
        }
        guard target.status != .skipped else {
            throw CoachToolError.mealAlreadySkipped(mealID)
        }

        target.status = .skipped
        try? modelContext.save()
        notifications?.cancelDefrostReminders(forMealID: target.id)
        notifications?.cancelPrepStartReminder(forMealID: target.id)
        notifications?.cancelOverdueMealReminder(forMealID: target.id)

        return ToolOutput(
            summary: "Marked \(target.mealName) as skipped.",
            sideEffects: [
                "Status: planned → skipped",
                "Notifications for this meal cancelled.",
                "(Macros not redistributed by this tool — agent will follow up if needed.)"
            ]
        )
    }

    // ── Swap to a quicker meal (recipe alternatives) ─────────────────────

    /// Surface 2-3 quicker-prep alternative recipes for a planned meal.
    /// Does NOT replace the meal — returns options the agent presents to
    /// the user; the user picks via follow-up turn (which triggers a
    /// separate update in a later iteration).
    ///
    /// v1: filters all Recipes by `totalMinutes <= maxPrepMin` and
    /// dietary tag overlap with the user's `DietaryProfile.restrictions`.
    /// Returns top 3 by macro proximity to the target meal's totals.
    /// Heavy lift (real recipe swap with regenerated ingredients) is v2.
    static func swapToQuickerMeal(
        mealID: UUID,
        maxPrepMin: Int,
        modelContext: ModelContext
    ) throws -> ToolOutput {
        let mealDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate { $0.id == mealID }
        )
        guard let meal = try? modelContext.fetch(mealDescriptor).first else {
            throw CoachToolError.mealNotFound(mealID)
        }
        guard meal.status == .planned else {
            if meal.status == .eaten { throw CoachToolError.mealAlreadyEaten(mealID) }
            if meal.status == .skipped { throw CoachToolError.mealAlreadySkipped(mealID) }
            throw CoachToolError.mealNotFound(mealID)
        }

        // Recipes are SwiftData @Models. Predicate-filter on totalMinutes.
        // (Predicate body can't access computed `totalMinutes`; we filter
        // in-memory after fetching candidates by archive flag.)
        let recipeDescriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.isArchived == false }
        )
        let allRecipes = (try? modelContext.fetch(recipeDescriptor)) ?? []
        let candidates = allRecipes.filter { $0.totalMinutes <= maxPrepMin }

        guard !candidates.isEmpty else {
            throw CoachToolError.noSuitableAlternative(
                reason: "No recipes with prep + cook ≤ \(maxPrepMin) minutes found."
            )
        }

        // Rank by macro proximity (lower distance = better fit).
        let ranked = candidates.sorted { a, b in
            macroDistance(meal: meal, recipe: a) < macroDistance(meal: meal, recipe: b)
        }.prefix(3)

        let lines = ranked.map { r in
            "\(r.name) — \(r.totalMinutes)min, \(Int(r.totalCalories))kcal / \(Int(r.totalProteinGrams))gP"
        }

        return ToolOutput(
            summary: "Found \(ranked.count) quicker alternative\(ranked.count == 1 ? "" : "s") for \(meal.mealName).",
            sideEffects: lines
        )
    }
}

// MARK: - ActivityImpact / MealPlacement

/// How an inserted activity affects today's meal plan beyond moving meals.
enum ActivityImpact: Sendable, Equatable {
    /// Just shifts the nearest meal; no day-type change.
    case shiftsMealsOnly
    /// Also flips today's day type (e.g. inserting soccer switches today
    /// from strength → soccer, bumping calorie targets).
    case changesDayType(DayType)
}

/// Where to place the moved meal relative to the activity window. Agent
/// decides based on reasoning (pre-activity light meal vs post-activity
/// recovery meal); tool just executes the math.
enum MealPlacement: Sendable, Equatable {
    /// Meal lands `bufferMin` minutes BEFORE activity start.
    /// Typical: 90min for a light pre-game meal.
    case beforeActivity(bufferMin: Int)
    /// Meal lands `bufferMin` minutes AFTER activity end.
    /// Typical: 30min for recovery meal.
    case afterActivity(bufferMin: Int)
}

// MARK: - Internal helpers

@MainActor
private func rescheduleMealNotifications(
    for meals: [PlannedMeal],
    notifications: (any NotificationServiceProtocol)?
) {
    guard let notifications else { return }
    let calendar = Calendar.current
    let now = Date()
    for meal in meals where meal.status == .planned {
        notifications.cancelDefrostReminders(forMealID: meal.id)
        notifications.cancelPrepStartReminder(forMealID: meal.id)
        notifications.cancelOverdueMealReminder(forMealID: meal.id)

        let mealTime = MealScheduleHelpers.scheduledDate(for: meal, calendar: calendar)
        guard mealTime > now else { continue }

        notifications.scheduleMealReminder(
            mealName: meal.mealName,
            time: mealTime.addingTimeInterval(-5 * 60)
        )
        notifications.scheduleOverdueMealReminder(
            mealID: meal.id,
            mealName: meal.mealName,
            scheduledTime: mealTime,
            lateMinutes: 15
        )
        let prepStart = MealScheduleHelpers.prepStartDate(for: meal, calendar: calendar)
        if prepStart > now, prepStart != mealTime {
            notifications.schedulePrepStartReminder(
                mealID: meal.id,
                mealName: meal.mealName,
                prepStartDate: prepStart
            )
        }
        // Defrost reminders re-fire only when we know ingredient lead times.
        // The agent can call this tool repeatedly; defrost reminders for new
        // meal plans are scheduled by MealPlanGeneratorService, not here.
    }
}

private func weekdayName(_ weekday: Int) -> String {
    switch weekday {
    case 1: return "Sunday"
    case 2: return "Monday"
    case 3: return "Tuesday"
    case 4: return "Wednesday"
    case 5: return "Thursday"
    case 6: return "Friday"
    case 7: return "Saturday"
    default: return "Day \(weekday)"
    }
}

/// Mirror of `TDEECalculator.caloriesMultiplier` so tool code doesn't
/// reach into the calculator. Kept in sync deliberately — if you change
/// the multipliers there, change them here.
private func caloriesMultiplier(for dayType: DayType) -> Double {
    switch dayType {
    case .rest: return 0.90
    case .cardio: return 1.10
    case .strength: return 1.00
    case .soccer: return 1.15
    case .double: return 1.25
    }
}

/// Sum of normalized macro deltas. Lower = better fit when ranking recipe
/// alternatives. Doesn't aim for chemical accuracy — just a heuristic so
/// the closest 3 candidates surface.
private func macroDistance(meal: PlannedMeal, recipe: Recipe) -> Double {
    let mealMacros = (meal.totalCalories, meal.totalProtein, meal.totalCarbs, meal.totalFat)
    let recipeMacros = (recipe.totalCalories, recipe.totalProteinGrams, recipe.totalCarbsGrams, recipe.totalFatGrams)
    func normDelta(_ a: Double, _ b: Double) -> Double {
        let scale = max(abs(a), abs(b), 1.0)
        return abs(a - b) / scale
    }
    return normDelta(mealMacros.0, recipeMacros.0)
        + normDelta(mealMacros.1, recipeMacros.1)
        + normDelta(mealMacros.2, recipeMacros.2)
        + normDelta(mealMacros.3, recipeMacros.3)
}
