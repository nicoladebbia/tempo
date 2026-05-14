//
// DayPlannerAIHydrator.swift
// Tempo
//
// Asynchronous AI copy hydration for an already-persisted DayPlan.
// Per docs/INTELLIGENCE_REMEDIATION_PLAN.md §9 + the architectural call:
// the §7 AI routes supply *copy only*. Block boundaries come from
// PlannedMeal / WorkoutPlan / EventKit — those are source of truth.
//
// Three routes fire in parallel via `async let`. Each one's failure is
// independent — a 402, a 503, or a network blip on one route leaves the
// other two's copy intact. The block stays usable with `copy == nil`;
// the timeline view renders the title and a "No AI rationale yet." note.
//

import Foundation
import SwiftData

@MainActor
final class DayPlannerAIHydrator {

    private let modelContext: ModelContext
    private let apiClient: APIClient

    init(modelContext: ModelContext, apiClient: APIClient) {
        self.modelContext = modelContext
        self.apiClient = apiClient
    }

    /// Hydrate the plan's training / meal / study blocks with AI copy.
    /// Idempotent: re-running overwrites existing copy with fresh
    /// rationale. Failure on any route is swallowed — partial hydration
    /// is better than all-or-nothing per ADR-014 (offline-first).
    func hydrate(plan: DayPlan, context: HydrationContext) async {
        // Pre-extract every meal block's identifying info BEFORE the
        // network fan-out — DayPlan / TimeBlock are non-Sendable
        // SwiftData @Model classes, so we can't hold references across
        // suspension points or pass them into Task closures. We re-bind
        // the captured copies to the model on the main actor afterwards.
        let mealMetas: [MealHydrationMeta] = plan.blocks
            .filter { $0.kind == .meal }
            .enumerated()
            .map { index, block in
                MealHydrationMeta(
                    sourceId: block.sourceId,
                    title: block.title,
                    mealIndex: index
                )
            }

        // Fan out the three call families in parallel.
        async let trainingCopy = fetchTrainingCopy(context: context)
        async let mealCopies = fetchMealCopies(metas: mealMetas, context: context)
        async let studyCopy = fetchStudyCopy(context: context)

        let training = await trainingCopy
        let meals = await mealCopies
        let study = await studyCopy

        // Apply on the main actor — touches @Model properties.
        applyTrainingCopy(training, to: plan)
        applyMealCopies(meals, to: plan)
        applyStudyCopy(study, to: plan)

        try? modelContext.save()
    }

    // MARK: - Per-route fetches (each safe in isolation)

    private func fetchTrainingCopy(context: HydrationContext) async -> String? {
        guard context.hasTrainingBlock else { return nil }
        let request = DayPlanTrainingProgramRequest(
            weekStart: context.weekStartString,
            footballDays: context.footballDays,
            recentRecovery7Day: context.recentRecovery7Day,
            recentSessions: context.recentSessions,
            goal: context.trainingGoal
        )
        do {
            let response: DayPlanTrainingProgramResponse = try await apiClient.request(
                .dayPlanTrainingProgram(),
                body: request
            )
            return response.rationale
        } catch {
            return nil
        }
    }

    /// Returns a map of PlannedMeal.id (as String) → AI note. Misses leave
    /// the corresponding block's copy untouched.
    private func fetchMealCopies(metas: [MealHydrationMeta], context: HydrationContext) async -> [String: String] {
        guard !metas.isEmpty else { return [:] }

        // Per-meal calls in parallel so a 5s p95 on one doesn't serialise.
        let apiClient = self.apiClient
        return await withTaskGroup(of: (String, String)?.self) { group in
            for meta in metas {
                guard let sourceId = meta.sourceId, !sourceId.isEmpty else { continue }
                let request = DayPlanMealTimingRequest(
                    date: context.dateString,
                    mealIndex: meta.mealIndex,
                    mealName: meta.title,
                    plannedCalories: 0,
                    plannedProteinGrams: 0,
                    trainingTimeToday: context.trainingTimeString,
                    lastMealTime: nil,
                    recoveryZone: context.recoveryZone
                )
                group.addTask {
                    do {
                        let response: DayPlanMealTimingResponse = try await apiClient.request(
                            .dayPlanMealTiming(),
                            body: request
                        )
                        return (sourceId, response.note)
                    } catch {
                        return nil
                    }
                }
            }
            var result: [String: String] = [:]
            for await pair in group {
                if let (id, note) = pair {
                    result[id] = note
                }
            }
            return result
        }
    }

    private func fetchStudyCopy(context: HydrationContext) async -> String? {
        guard context.hasStudyBlock, let exam = context.nextExam else { return nil }
        let request = DayPlanStudyScheduleRequest(
            examId: exam.id,
            examName: exam.name,
            daysUntilExam: exam.daysUntil,
            topics: exam.topics,
            topicProgress: exam.topicProgress,
            dailyAvailabilityMinutes: context.studyAvailabilityMinutes
        )
        do {
            let response: DayPlanStudyScheduleResponse = try await apiClient.request(
                .dayPlanStudySchedule(),
                body: request
            )
            return response.rationale
        } catch {
            return nil
        }
    }

    // MARK: - Apply

    private func applyTrainingCopy(_ copy: String?, to plan: DayPlan) {
        guard let copy else { return }
        for block in plan.blocks where block.kind == .training {
            block.copy = copy
        }
    }

    private func applyMealCopies(_ copies: [String: String], to plan: DayPlan) {
        for block in plan.blocks where block.kind == .meal {
            if let id = block.sourceId, let note = copies[id] {
                block.copy = note
            }
        }
    }

    private func applyStudyCopy(_ copy: String?, to plan: DayPlan) {
        guard let copy else { return }
        for block in plan.blocks where block.kind == .study {
            block.copy = copy
        }
    }
}

// MARK: - MealHydrationMeta

/// Sendable snapshot of a meal block's identity. Used to ferry data into
/// the per-meal task group without carrying the non-Sendable TimeBlock
/// across a suspension point.
private struct MealHydrationMeta: Sendable {
    let sourceId: String?
    let title: String
    let mealIndex: Int
}

// MARK: - HydrationContext

/// Everything the hydrator needs to build the three §7 payloads. Caller
/// (typically `DayPlannerService` after a successful solve) assembles
/// this from local sources so the hydrator stays Sendable + pure-ish.
struct HydrationContext: Sendable {
    /// "yyyy-MM-dd" for today.
    let dateString: String
    /// "yyyy-MM-dd" for the start of this week (Sunday or Monday per
    /// `Calendar.current.firstWeekday`).
    let weekStartString: String

    /// Whether the solver placed a training block — skip the training-
    /// program call when false to save a Claude credit + AI budget hit.
    let hasTrainingBlock: Bool

    /// Whether the solver placed at least one study block.
    let hasStudyBlock: Bool

    /// Football days as lowercase weekday names this week. Used by
    /// training-program. Empty when the user isn't playing this week.
    let footballDays: [String]

    /// Last 7 daily Whoop recovery scores, today inclusive. Caller pads
    /// with the most recent known value when a day is missing.
    let recentRecovery7Day: [Int]

    /// Brief one-line summaries of the last ~4 sessions, oldest first.
    let recentSessions: [String]

    /// "hypertrophy" / "strength" / "fat_loss" — from user goals.
    let trainingGoal: String

    /// Today's recovery zone — "green" / "yellow" / "red".
    let recoveryZone: String

    /// "HH:mm" when a workout is placed today, nil when not training.
    /// Lets meal-timing align around the workout window.
    let trainingTimeString: String?

    /// Pomodoro length + count, as minutes available for study today.
    let studyAvailabilityMinutes: Int

    /// Next upcoming exam, when there is one. Required by study-schedule.
    let nextExam: ExamHydrationContext?
}

struct ExamHydrationContext: Sendable {
    let id: String
    let name: String
    let daysUntil: Int
    let topics: [String]
    let topicProgress: [String: Int]
}
