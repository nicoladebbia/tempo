//
// SupplementScheduleEngine.swift
// Tempo
//
// Decides WHEN each owned supplement is taken today — a pure, no-SwiftData
// function of the shelf + a day's context (meals, training, wake/bed, and the
// plan AI's take/skip decisions). The Today card and the reminder scheduler
// both read its output (`SupplementDose`) instead of duplicating the timing
// logic.
//
// Priority for WHEN (highest wins):
//   1. `Supplement.pinnedMinutes` — user pinned an exact clock time.
//   2. `Supplement.timingAnchorOverride` — user picked an anchor (breakfast,
//      bedtime, ...).
//   3. The plan AI's free-text `SupplementDecision.timing`, parsed into an
//      anchor (only when the decision says take — a skip has no timing text).
//   4. A default by kind (`SupplementTimingAnchor.defaultAnchor(for:)`), with
//      a name heuristic checked first for supplements whose kind is generic
//      (a "Vitamin / Mineral" named "Magnesium Glycinate" should anchor to
//      bedtime, not the kind's breakfast default).
//
// WHETHER to take it follows the plan's decision when one exists; with no
// plan, `takeDaily` items are taken every day, protein/pre-workout/
// electrolytes only on training days, and everything else daily — so
// guidance works from day one, before the user ever generates a meal plan.
//

import Foundation

// MARK: - SupplementMealTime

/// One of today's planned meals, reduced to just what the engine needs to
/// anchor "with breakfast" / "with lunch" / "with dinner" to a real clock
/// time. Built from `PlannedMeal` by the caller (`SupplementDayContext.build`).
struct SupplementMealTime: Equatable, Sendable {
    let mealNumber: Int
    let mealName: String
    /// Minutes after midnight, parsed from `PlannedMeal.scheduledTime`.
    let minutes: Int
}

private extension [SupplementMealTime] {
    /// Prefers a name match ("Breakfast", "Post-workout snack") over the
    /// positional `mealNumber`, since a shifted plan (meal skipped/moved) can
    /// leave the number pointing at the wrong slot but the name is authored
    /// fresh each generation.
    func time(matchingNumber number: Int, name: String) -> Int? {
        if let byName = first(where: { $0.mealName.lowercased().contains(name) }) {
            return byName.minutes
        }
        return first(where: { $0.mealNumber == number })?.minutes
    }
}

// MARK: - SupplementDayContext

/// Everything the engine needs to resolve anchors to real clock minutes for
/// one day, and to make a no-plan take/skip call. Callers build this from
/// SwiftData (`SupplementDayContext.build` in `SupplementReminderScheduler`);
/// tests build it by hand.
struct SupplementDayContext: Equatable, Sendable {
    /// The plan AI's decisions for this day, keyed by `Supplement.name`.
    /// Empty when no plan covers the day — the engine then uses its own
    /// no-plan defaults for both timing and take/skip.
    var planDecisions: [String: SupplementDecision]
    /// True when training happens today (routine slot, trainer program, or
    /// the plan's day type) — drives the no-plan protein/electrolytes/
    /// pre-workout rule and the pre/post-training anchor fallback time.
    var isTrainingDay: Bool
    var trainingStartMinutes: Int?
    var trainingEndMinutes: Int?
    var wakeMinutes: Int
    var bedMinutes: Int
    var meals: [SupplementMealTime]

    static let defaultWakeMinutes = 7 * 60 + 30 // 07:30
    static let defaultBedMinutes = 23 * 60 // 23:00
    static let defaultBreakfastMinutes = 8 * 60 // 08:00
    static let defaultLunchMinutes = 13 * 60 // 13:00
    static let defaultDinnerMinutes = 19 * 60 + 30 // 19:30
    /// Same fallback `TrainerSessionReminderScheduler.timeOfDay` uses for
    /// `.anyFree` / no profile — the most common after-work training slot.
    static let defaultTrainingStartMinutes = 17 * 60 // 17:00
    static let defaultTrainingDurationMinutes = 60

    init(
        planDecisions: [String: SupplementDecision] = [:],
        isTrainingDay: Bool = false,
        trainingStartMinutes: Int? = nil,
        trainingEndMinutes: Int? = nil,
        wakeMinutes: Int = SupplementDayContext.defaultWakeMinutes,
        bedMinutes: Int = SupplementDayContext.defaultBedMinutes,
        meals: [SupplementMealTime] = []
    ) {
        self.planDecisions = planDecisions
        self.isTrainingDay = isTrainingDay
        self.trainingStartMinutes = trainingStartMinutes
        self.trainingEndMinutes = trainingEndMinutes
        self.wakeMinutes = wakeMinutes
        self.bedMinutes = bedMinutes
        self.meals = meals
    }
}

// MARK: - SupplementTimeSource

/// Which priority tier resolved a dose's anchor — kept on `SupplementDose` so
/// UI/tests can tell an explicit override from a guess.
enum SupplementTimeSource: Equatable, Sendable {
    case pinned
    case anchorOverride(SupplementTimingAnchor)
    case planTiming(SupplementTimingAnchor)
    case kindDefault(SupplementTimingAnchor)

    /// nil only for `.pinned`, which has no anchor — just a raw clock time.
    var anchor: SupplementTimingAnchor? {
        switch self {
        case .pinned: nil
        case let .anchorOverride(a),
             let .planTiming(a),
             let .kindDefault(a): a
        }
    }
}

// MARK: - SupplementDose

/// One supplement's resolved plan for today: take or skip, when, and why.
struct SupplementDose: Identifiable, Equatable, Sendable {
    let supplementID: UUID
    let name: String
    let kind: SupplementKind
    let dosePerServing: String
    let take: Bool
    /// Minutes after midnight — always resolved, even for a skip, so the
    /// Today card can sort take/skip rows together in one chronological list.
    let minutes: Int
    /// nil only when the time came from a raw pinned minute with no anchor.
    let anchor: SupplementTimingAnchor?
    let reason: String
    /// True only when the plan AI explicitly decided "skip today". A skip the
    /// engine inferred on its own (rest day, no plan) is not a decision.
    var skippedByPlan = false

    var id: UUID {
        supplementID
    }

    var timeLabel: String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    /// "With breakfast" / "Fixed time" — for a pinned dose with no anchor.
    var timingLabel: String {
        anchor?.displayName ?? "Fixed time"
    }
}

// MARK: - SupplementDoseGroup

/// Doses that land at the same clock minute — one reminder notification per
/// group ("Breakfast: Creatine + Vitamin D3"), not one per supplement.
struct SupplementDoseGroup: Equatable, Sendable {
    let minutes: Int
    /// TAKE doses only, sorted by name for a stable notification body.
    let doses: [SupplementDose]

    var names: [String] {
        doses.map(\.name)
    }

    var timeLabel: String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

// MARK: - SupplementNameHeuristic

/// Name-based anchor guesses that beat the generic kind default — a
/// "Vitamin / Mineral" named "Magnesium Glycinate" should anchor to bedtime,
/// not the vitamin kind's breakfast default.
enum SupplementNameHeuristic {
    private static let bedtimeNames = ["magnesium", "zinc", "melatonin", "ashwagandha", "glycine"]
    private static let breakfastNames = ["vitamin d", "vitamin k", "multivitamin"]
    private static let dinnerNames = ["fish oil", "omega"]
    private static let preTrainingNames = ["caffeine", "pre-workout", "preworkout", "pre workout"]
    private static let postTrainingNames = ["protein", "whey", "casein"]

    static func anchor(forName name: String) -> SupplementTimingAnchor? {
        let n = name.lowercased()
        if bedtimeNames.contains(where: n.contains) {
            return .bedtime
        }
        if breakfastNames.contains(where: n.contains) {
            return .breakfast
        }
        if dinnerNames.contains(where: n.contains) {
            return .dinner
        }
        if preTrainingNames.contains(where: n.contains) {
            return .preTraining
        }
        if postTrainingNames.contains(where: n.contains) {
            return .postTraining
        }
        return nil
    }
}

// MARK: - SupplementTimingParser

/// Parses the plan AI's free-text timing ("after lunch", "post-training")
/// into a `SupplementTimingAnchor`. Order matters: compound phrases are
/// checked before the single words they contain (e.g. "training" appears in
/// both the pre- and post-training phrases).
enum SupplementTimingParser {
    static func anchor(fromPlanTiming text: String) -> SupplementTimingAnchor? {
        let t = text.lowercased()
        if t.contains("bed") {
            return .bedtime
        }
        if ["post-training", "post training", "after training", "post-workout", "post workout", "after workout"]
            .contains(where: t.contains)
        {
            return .postTraining
        }
        if ["pre-training", "pre training", "before training", "pre-workout", "preworkout", "pre workout"]
            .contains(where: t.contains)
        {
            return .preTraining
        }
        if t.contains("breakfast") {
            return .breakfast
        }
        if t.contains("lunch") {
            return .lunch
        }
        if t.contains("dinner") {
            return .dinner
        }
        if t.contains("wak") {
            return .wake
        }
        if t.contains("morning") {
            return .breakfast
        }
        return nil
    }
}

// MARK: - SupplementScheduleEngine

enum SupplementScheduleEngine {
    /// Monday=1 … Sunday=7 — the convention `WeeklyRoutine`, `WeeklyMealPlan.
    /// dayTypeAssignments` and `WeeklyMealPlan.supplementDecisions` all share
    /// (`MealPlanGeneratorService` writes `dayIndex + 1`, dayIndex 0 = Monday).
    /// `Calendar.component(.weekday:)` is 1 = Sunday … 7 = Saturday, so this
    /// rotates it.
    static func mondayFirstWeekday(for date: Date, calendar: Calendar = .current) -> Int {
        let sundayFirst = calendar.component(.weekday, from: date) // 1 = Sunday … 7 = Saturday
        return (sundayFirst + 5) % 7 + 1
    }

    // MARK: Take / skip

    static func resolveTakeDecision(
        supplement: Supplement,
        planDecision: SupplementDecision?,
        isTrainingDay: Bool
    ) -> (take: Bool, reason: String) {
        if let planDecision {
            let trimmed = planDecision.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reason = trimmed.isEmpty
                ? (planDecision.take ? "Per your plan" : "Skip per your plan")
                : trimmed
            return (planDecision.take, reason)
        }
        if supplement.takeDaily {
            return (true, "Daily")
        }
        switch supplement.kind {
        case .protein,
             .preworkout,
             .electrolytes:
            return isTrainingDay ? (true, "Training day") : (false, "Rest day — nothing to fuel")
        case .creatine,
             .omega3,
             .multivitamin,
             .vitamin,
             .other:
            return (true, "Daily")
        }
    }

    // MARK: Timing source

    static func resolveTimeSource(supplement: Supplement, planDecision: SupplementDecision?) -> SupplementTimeSource {
        if supplement.pinnedMinutes != nil {
            return .pinned
        }
        if let override = supplement.timingAnchorOverride {
            return .anchorOverride(override)
        }
        if let planDecision, planDecision.take,
           let timing = planDecision.timing,
           let parsed = SupplementTimingParser.anchor(fromPlanTiming: timing)
        {
            return .planTiming(parsed)
        }
        let fallback = SupplementNameHeuristic.anchor(forName: supplement.name)
            ?? SupplementTimingAnchor.defaultAnchor(for: supplement.kind)
        return .kindDefault(fallback)
    }

    // MARK: Anchor → clock minutes

    static func minutes(for anchor: SupplementTimingAnchor, context: SupplementDayContext) -> Int {
        switch anchor {
        case .wake:
            context.wakeMinutes
        case .bedtime:
            context.bedMinutes
        case .breakfast:
            context.meals.time(matchingNumber: 1, name: "breakfast") ?? SupplementDayContext.defaultBreakfastMinutes
        case .lunch:
            context.meals.time(matchingNumber: 2, name: "lunch") ?? SupplementDayContext.defaultLunchMinutes
        case .dinner:
            context.meals.time(matchingNumber: 3, name: "dinner") ?? SupplementDayContext.defaultDinnerMinutes
        case .preTraining:
            (context.trainingStartMinutes ?? SupplementDayContext.defaultTrainingStartMinutes) - 30
        case .postTraining:
            context.trainingEndMinutes
                ?? ((context.trainingStartMinutes ?? SupplementDayContext.defaultTrainingStartMinutes)
                    + SupplementDayContext.defaultTrainingDurationMinutes)
        }
    }

    static func resolveMinutes(source: SupplementTimeSource, supplement: Supplement, context: SupplementDayContext) -> Int {
        if case .pinned = source, let pinned = supplement.pinnedMinutes {
            return pinned
        }
        guard let anchor = source.anchor else {
            return context.wakeMinutes
        }
        return minutes(for: anchor, context: context)
    }

    // MARK: Dose / schedule

    static func dose(for supplement: Supplement, context: SupplementDayContext) -> SupplementDose {
        let planDecision = context.planDecisions[supplement.name]
        let (take, reason) = resolveTakeDecision(supplement: supplement, planDecision: planDecision, isTrainingDay: context.isTrainingDay)
        let source = resolveTimeSource(supplement: supplement, planDecision: planDecision)
        let resolvedMinutes = resolveMinutes(source: source, supplement: supplement, context: context)
        var dose = SupplementDose(
            supplementID: supplement.id,
            name: supplement.name,
            kind: supplement.kind,
            dosePerServing: supplement.dosePerServing,
            take: take,
            minutes: resolvedMinutes,
            anchor: source.anchor,
            reason: reason
        )
        dose.skippedByPlan = planDecision != nil && !take
        return dose
    }

    /// Today's full shelf, sorted chronologically (ties broken by name so the
    /// order is stable across calls).
    static func schedule(supplements: [Supplement], context: SupplementDayContext) -> [SupplementDose] {
        supplements
            .filter { !$0.isArchived }
            .map { dose(for: $0, context: context) }
            .sorted { $0.minutes == $1.minutes ? $0.name < $1.name : $0.minutes < $1.minutes }
    }

    /// TAKE doses only, grouped by clock minute — the reminder scheduler's
    /// input. `dosesForDay` need not be pre-sorted.
    static func group(dosesForDay doses: [SupplementDose]) -> [SupplementDoseGroup] {
        let taken = doses.filter(\.take)
        let byMinute = Dictionary(grouping: taken, by: \.minutes)
        return byMinute.keys.sorted().map { minute in
            SupplementDoseGroup(minutes: minute, doses: (byMinute[minute] ?? []).sorted { $0.name < $1.name })
        }
    }
}
