//
// TrainingViewModel+PlanResolution.swift
// Tempo
//
// Plan resolution guard (Tier 3.1) — decides whether today's plan is
// reused, regenerated, or resumed from a crashed in-progress session.
// Split out of TrainingViewModel.swift to keep it under the SwiftLint
// file/type-body length caps — same instance methods, hosted in an extension.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Plan Resolution Guard (Tier 3.1, pure + unit-tested)

    /// Whether an existing persisted day-row should be KEPT or REPLACED when the
    /// forward-looking week template disagrees with it (e.g. after the user
    /// edits football days / split). This is the data-loss invariant: a
    /// `.completed` or `.inProgress` row is SACRED — it records real training (and
    /// owns ExerciseHistory) — and must never be replaced, regardless of type.
    /// Only a still-`.planned` row may be replaced, and only when its type
    /// actually differs from the template.
    enum PlanResolution: Equatable {
        case keep
        case replace
    }

    nonisolated static func planResolution(
        existingStatus: WorkoutStatus,
        existingType: WorkoutType,
        existingPlannedTypeRaw: String? = nil,
        templateType: WorkoutType
    ) -> PlanResolution {
        switch existingStatus {
        case .planned:
            if existingType == templateType {
                return .keep
            }
            // §8 connect — the row WAS the template type before the daily
            // brain moved it (planned pool → rest at yellow). The mismatch is
            // deliberate; replacing would resurrect the desync every app-open.
            // If the TEMPLATE itself changed (user edited the schedule), the
            // stash no longer matches and the template rightly wins.
            if existingPlannedTypeRaw == templateType.rawValue {
                return .keep
            }
            return .replace
        default:
            // completed / inProgress / skipped — sacred, never replace.
            return .keep
        }
    }

    /// Pure merge for the Week Plan / Today / Dashboard identity problem:
    /// `assembleWeekPlans` (loadWeekPlan, hydrateWeekWithAI) always returns
    /// FRESH transient WorkoutPlan objects, while today's (and any completed/
    /// in-progress day's) real state lives on a PERSISTED row. Substitutes the
    /// persisted object for any transient slot that is either dated `today` or
    /// backed by a sacred (completed/in-progress) persisted row — every other
    /// slot passes through untouched, so an AI-hydrated in-place adjustment
    /// (`hydrateWeekWithAI`) to a non-sacred future day is never silently lost.
    /// When two persisted rows exist for the same day (a transient duplicate
    /// left over before `ensureTodayPlanPersisted` cleans it up), the more
    /// sacred one wins: in-progress > completed > planned.
    nonisolated static func mergePersistedIntoWeek(
        _ transient: [WorkoutPlan],
        persisted: [WorkoutPlan],
        today: Date,
        calendar: Calendar = .current
    ) -> [WorkoutPlan] {
        guard !persisted.isEmpty else {
            return transient
        }
        func sacrednessRank(_ status: WorkoutStatus) -> Int {
            switch status {
            case .inProgress: 2
            case .completed: 1
            case .planned,
                 .skipped: 0
            }
        }
        var byDay: [Date: WorkoutPlan] = [:]
        for plan in persisted {
            let day = calendar.startOfDay(for: plan.date)
            if let existing = byDay[day] {
                if sacrednessRank(plan.status) > sacrednessRank(existing.status) {
                    byDay[day] = plan
                }
            } else {
                byDay[day] = plan
            }
        }
        let todayKey = calendar.startOfDay(for: today)
        return transient.map { slot in
            let day = calendar.startOfDay(for: slot.date)
            guard let match = byDay[day] else {
                return slot
            }
            guard match.status == .completed || match.status == .inProgress || day == todayKey else {
                return slot
            }
            return match
        }
    }

    /// Ensures today's WorkoutPlan exists and is PERSISTED, returning it.
    /// Extracted from loadToday so DailyResetCoordinator can call the exact
    /// same path — the Dashboard's Move quadrant only reads the persisted
    /// row, so this guarantees Dashboard and Training never disagree about
    /// today's workout. Idempotent: an existing matching plan is returned
    /// untouched (preserving logged sets); a stale-type plan is replaced
    /// with the canonical Week Plan version.
    @discardableResult
    func ensureTodayPlanPersisted(modelContext: ModelContext) -> ResolvedTodayPlan {
        // Week Plan must be loaded first so Today and Week Plan agree.
        if weekPlans.isEmpty {
            loadWeekPlan(modelContext: modelContext)
        }
        let today = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            // Pathological calendar — fall through to a fresh generate.
            return generateAndPersist(for: today, modelContext: modelContext)
        }
        let weekPlanForToday = weekPlans.first { Calendar.current.isDate($0.date, inSameDayAs: today) }

        // RANGE predicate (not `== today`) so we also catch any legacy row
        // persisted with a non-midnight date. The Dashboard's Move quadrant
        // uses the SAME range — using `== today` here while Dashboard used a
        // range is exactly how "Pull on Dashboard, Rest in Training" happened:
        // two rows for one day, each surface picking a different one.
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { plan in
                plan.date >= today && plan.date < tomorrow
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allToday = (try? modelContext.fetch(descriptor)) ?? []

        // Pick the canonical survivor by SACREDNESS, not recency: an
        // in-progress session wins, then a completed one (it holds the day's
        // logged training + its ExerciseHistory), then the most recent planned
        // row. Picking by recency let a fresh .planned dupe outrank — and then
        // delete — a .completed plan, destroying that day's history.
        let survivor = allToday.first { $0.status == .inProgress }
            ?? allToday.first { $0.status == .completed }
            ?? allToday.first
        if allToday.count > 1 {
            for dupe in allToday where dupe !== survivor {
                // NEVER delete a plan that holds real training. Only planned/
                // skipped scaffolding rows are safe to collapse as duplicates.
                guard dupe.status != .completed, dupe.status != .inProgress else {
                    continue
                }
                modelContext.delete(dupe)
            }
            try? modelContext.save()
        }

        if let existing = survivor {
            if existing.status == .inProgress {
                return ResolvedTodayPlan(plan: existing, isCrashedInProgress: true)
            }
            if let canonical = weekPlanForToday,
               Self.planResolution(
                   existingStatus: existing.status,
                   existingType: existing.type,
                   existingPlannedTypeRaw: existing.plannedTypeRaw,
                   templateType: canonical.type
               ) == .replace
               // A trainer program was started/changed/stopped: a still-
               // planned row from a different (or no) program session is
               // stale even when the day's type happens to match.
               || (existing.status == .planned
                   && existing.programSessionKey != canonical.programSessionKey)
            {
                // Only a still-PLANNED row whose type differs may be replaced
                // (e.g. user changed Football Days). A completed/in-progress plan
                // is sacred — planResolution returns .keep for it — so it
                // survives even if its type no longer matches the template.
                // (This was a data-loss path before the guard: deleting a
                // completed plan orphaned its history.)
                modelContext.delete(existing)
                populateExercises(for: canonical, modelContext: modelContext)
                modelContext.insert(canonical)
                try? modelContext.save()
                return ResolvedTodayPlan(plan: canonical, isCrashedInProgress: false)
            }
            // Keep it — matches the Week Plan type, OR holds real training
            // (completed/in-progress) and must be preserved regardless of type.
            // BUT a still-PLANNED day must pick up planning-only attributes the
            // fresh template gained since it was persisted — specifically the §21
            // two-a-day second session (added by a newer build, or by today
            // flipping green). Without this, the persisted plan keeps
            // secondary=nil while the freshly-generated Week view shows "+RUN":
            // the Today card and Week view desync, and the daily coach never
            // composes the second part. Sync ONLY the planning attribute, ONLY
            // while .planned (never mutate a completed/in-progress day's state).
            if existing.status == .planned,
               let canonical = weekPlanForToday,
               existing.secondarySessionTypeRaw != canonical.secondarySessionTypeRaw
            {
                existing.secondarySessionTypeRaw = canonical.secondarySessionTypeRaw
                if canonical.secondarySessionTypeRaw == nil {
                    existing.secondaryCompleted = false
                }
                try? modelContext.save()
            }
            // Backstop for EVERY path that can leave a still-planned gym row
            // unstartable: no exercises at all (coach flipped football → upper
            // on a bare row), or exercises whose sets are missing/warmup-only
            // (§11.13 — landing on one froze the session). A planned row holds
            // no logged training, so wiping and rebuilding loses nothing.
            if existing.status == .planned, existing.type.isGymWorkout {
                let broken = existing.orderedExercises.isEmpty
                    || existing.orderedExercises.contains { pe in
                        !(pe.sets ?? []).contains { !$0.isWarmup }
                    }
                if broken {
                    for pe in existing.orderedExercises {
                        modelContext.delete(pe)
                    }
                    existing.exercises = []
                    populateExercises(for: existing, modelContext: modelContext)
                    snapPrescribedWeights(for: existing, modelContext: modelContext)
                    try? modelContext.save()
                }
            }
            return ResolvedTodayPlan(plan: existing, isCrashedInProgress: false)
        }

        if let canonical = weekPlanForToday {
            populateExercises(for: canonical, modelContext: modelContext)
            modelContext.insert(canonical)
            try? modelContext.save()
            return ResolvedTodayPlan(plan: canonical, isCrashedInProgress: false)
        }

        return generateAndPersist(for: today, modelContext: modelContext)
    }

    /// Single-day generate-and-persist fallback used when the Week Plan
    /// produced nothing for today.
    private func generateAndPersist(for _: Date, modelContext: ModelContext) -> ResolvedTodayPlan {
        let footballDays = loadFootballDays(modelContext: modelContext)
        let split = loadTrainingSplit(modelContext: modelContext)
        let recoveryScore = loadRecoveryScore(modelContext: modelContext)
        let plan = trainingEngine.generateWorkout(
            for: Date(),
            recoveryScore: recoveryScore,
            footballDays: footballDays,
            split: split,
            // Same map the weekly path reads — without it this fallback used
            // the split rotation and disagreed with the Week view under Custom.
            customWeekdayMap: loadCustomWeekdayPlan(modelContext: modelContext)
        )
        // §19.3 full-rest deload — keep the single-day fallback consistent
        // with the weekly transform (gym day → mobility on a deload week).
        let deload = loadDeloadSettings(modelContext: modelContext)
        if deload.enabled, deload.style == .fullRest, plan.type.isGymWorkout,
           trainingEngine.isDeloadWeek(
               date: Date(),
               deloadFrequencyWeeks: deload.frequency,
               trainingStartDate: deload.startDate,
               fatigueEWMA: adaptiveSignals(modelContext: modelContext).fatigueEWMA
           )
        {
            plan.type = .mobility
            plan.notes = "Deload — full rest week. Move, stretch, recover."
        }
        // Same trainer-program overlay as the weekly path.
        if let program = activeTrainerProgram(modelContext: modelContext) {
            let cal = Calendar.current
            let matchDays = Set(fetchUpcomingMatches(modelContext: modelContext).map { cal.startOfDay(for: $0.kickoff) })
            Self.applyTrainerProgram(program, to: [plan], matchDayKeys: matchDays)
        }
        populateExercises(for: plan, modelContext: modelContext)
        modelContext.insert(plan)
        try? modelContext.save()
        return ResolvedTodayPlan(plan: plan, isCrashedInProgress: false)
    }
}
