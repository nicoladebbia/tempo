//
// TrainingViewModel+Measurement.swift
// Tempo
//
// Measurement spine (prediction accuracy + outcomes), error-fit correction
// and the adaptive profile (Phase 3). Split out of TrainingViewModel.swift to
// keep it under the SwiftLint file/type-body length caps — same instance
// methods, hosted in an extension.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Prediction Accuracy (Step 2 measurement spine — read-only)

    /// Compute the prediction-accuracy summary from all resolved PredictionLog
    /// rows. PASSIVE: this only measures whether the engine is getting more
    /// accurate for this user — it does NOT feed back into prescriptions yet.
    /// The honest readout for "is it actually learning?"
    func predictionAccuracy(modelContext: ModelContext) -> AccuracySummary {
        let descriptor = FetchDescriptor<PredictionLog>(
            predicate: #Predicate { $0.outcomeResolved }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return PredictionAccuracy.summarize(rows)
    }

    /// §14 #3 — session-level accuracy: the brain's expectedSessionRPE vs the
    /// user's one-tap actual on the linked plan. Relationship traversal stays
    /// out of the #Predicate (SwiftData optional-chain predicates are fragile);
    /// the join is filtered in memory — row counts here are tiny (1/day).
    func sessionRPEAccuracy(modelContext: ModelContext) -> SessionRPEAccuracy {
        let descriptor = FetchDescriptor<DailySession>(
            predicate: #Predicate { $0.expectedSessionRPE != nil }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let pairs = rows.compactMap { session -> SessionRPEPair? in
            // Read the DENORMALIZED actual, never `session.workoutPlan?.sessionRPE`:
            // that link is a one-way `.nullify` and a history-deleted plan leaves
            // it dangling → traversing crashes (invalidated backing).
            guard let expected = session.expectedSessionRPE,
                  let actual = session.actualSessionRPE else { return nil }
            return SessionRPEPair(date: session.date, expected: expected, actual: actual)
        }
        return PredictionAccuracy.summarizeSessions(pairs)
    }

    /// Step 4 hold-out: does the personalized engine actually beat the generic
    /// +2.5kg/week baseline on prediction error? Read-only / passive — the
    /// honesty check. Returns `.insufficient` until enough resolved rows exist.
    func predictionHoldout(modelContext: ModelContext) -> HoldoutResult {
        let descriptor = FetchDescriptor<PredictionLog>(
            predicate: #Predicate { $0.outcomeResolved }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return PredictionAccuracy.holdout(rows)
    }

    // MARK: - Prediction Outcomes (Step 1 measurement spine)

    /// One exercise's observed outcome, decoupled from the persistCompletion-
    /// local HistorySnapshot so this helper is callable + testable on its own.
    struct PredictionOutcome {
        let exerciseID: UUID
        let bestSetReps: Int?
        let avgRPE: Double?
        let worstFormRaw: String?
        let bestSetWeight: Double?
    }

    /// Fill the actual-outcome fields on this plan's PredictionLog rows from the
    /// just-completed session. Matched by (workoutPlanID, exerciseID). Marks each
    /// matched row `outcomeResolved` so it's never re-clobbered and Step 2 can
    /// score it. An outcome with no matching prediction (e.g. an exercise added
    /// mid-session) is skipped — predictions only exist for what was prescribed.
    func backfillPredictionOutcomes(
        planID: UUID,
        outcomes: [PredictionOutcome],
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<PredictionLog>(
            predicate: #Predicate { $0.workoutPlanID == planID }
        )
        guard let rows = try? modelContext.fetch(descriptor), !rows.isEmpty else { return }
        let byExercise = Dictionary(rows.map { ($0.exerciseID, $0) }) { first, _ in first }

        for outcome in outcomes {
            guard let log = byExercise[outcome.exerciseID] else { continue }
            log.actualReps = outcome.bestSetReps
            log.actualRPE = outcome.avgRPE
            log.actualFormRaw = outcome.worstFormRaw
            log.actualWeight = outcome.bestSetWeight
            log.outcomeResolved = true
        }
    }

    // MARK: - Error-Fit Correction (Step 3 — measure → correct)

    /// After outcomes are backfilled, fit each exercise's learned increment to
    /// its MEASURED signed RPE error (conservative partial step, clamped). This
    /// is the error-driven replacement for the blind RPE-bucket nudge: instead
    /// of "+10% because it felt easy", it's "this exercise lands 1.2 RPE under
    /// target, so nudge the step toward the value that would've hit target."
    /// Only acts on the predictions resolved THIS session.
    func applyErrorFitCorrection(planID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PredictionLog>(
            predicate: #Predicate { $0.workoutPlanID == planID && $0.outcomeResolved }
        )
        let resolved = (try? modelContext.fetch(descriptor)) ?? []
        guard !resolved.isEmpty else { return }

        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)

        // One correction per exercise, from this session's measured error.
        let byExercise = Dictionary(grouping: resolved, by: { $0.exerciseID })
        for (exerciseID, rows) in byExercise {
            let errors = rows.compactMap(\.rpeError)
            guard !errors.isEmpty else { continue }
            let meanError = errors.reduce(0, +) / Double(errors.count)

            // Current learned step, or the one used at prescribe time, or the
            // equipment default the prediction recorded.
            let current = profile.learnedIncrements[exerciseID]
                ?? rows.first?.learnedIncrementUsed
                ?? 2.5
            let corrected = AdaptiveProfileUpdater.correctedIncrement(
                current: current,
                meanSignedRPEError: meanError
            )
            profile.learnedIncrements[exerciseID] = corrected
        }
        profile.updatedAt = Date()
        try? modelContext.save()
        #if DEBUG
            print("\(DebugTrace.prefix)[adaptive] error-fit correction applied for \(byExercise.count) exercise(s)")
        #endif
    }

    // MARK: - Adaptive Profile (Phase 3)

    /// Read-only snapshot of the adaptive signals the engine consumes. Does NOT
    /// create a profile row (creation only happens on save) — returns neutral
    /// defaults when none exists yet, so a brand-new user runs the pure floor.
    func adaptiveSignals(modelContext: ModelContext)
        -> (thresholdOffset: Double, fatigueEWMA: Double?, learnedIncrements: [UUID: Double]) {
        guard let profile = try? modelContext.fetch(FetchDescriptor<AdaptiveProfile>()).first else {
            return (0, nil, [:])
        }
        return (profile.clampedThresholdOffset, profile.fatigueEWMA, profile.learnedIncrements)
    }

    /// Fetch the single AdaptiveProfile, creating it on first use. Internal
    /// (not private) so the split extension files (+ExercisePopulation's swap
    /// preferences) reach the same row.
    func fetchOrCreateAdaptiveProfile(modelContext: ModelContext) -> AdaptiveProfile {
        if let existing = try? modelContext.fetch(FetchDescriptor<AdaptiveProfile>()).first {
            return existing
        }
        let profile = AdaptiveProfile()
        modelContext.insert(profile)
        return profile
    }

    /// Feed a saved session into the on-device AdaptiveProfile (bounded online
    /// learning). The base-increment closure mirrors the engine's equipment
    /// defaults so a never-seen exercise starts from the right step.
    func updateAdaptiveProfile(with session: [ExerciseHistory], modelContext: ModelContext) {
        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)
        AdaptiveProfileUpdater.ingest(
            session: session,
            baseIncrement: { row in
                switch row.exercise?.equipment {
                case .barbell: 2.5
                case .dumbbell: 2.0
                case .cable, .machine: 2.5
                default: 2.5
                }
            },
            into: profile
        )
        try? modelContext.save()
        #if DEBUG
            print("\(DebugTrace.prefix)[adaptive] profile updated: offset=\(profile.recoveryThresholdOffset) fatigueEWMA=\(profile.fatigueEWMA.map { String(format: "%.2f", $0) } ?? "nil") learnedExercises=\(profile.learnedIncrements.count)")
        #endif
    }

    /// Short summaries of the last 4 completed sessions for the AI prompt.
    func loadRecentSessionSummaries(modelContext: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<ExerciseHistory>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 16 // a few exercises per session, last few sessions
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        // Group by day, summarize tonnage + avg RPE.
        let byDay = Dictionary(grouping: rows) { $0.date }
        let recentDays = byDay.keys.sorted(by: >).prefix(4)
        return recentDays.map { day in
            let dayRows = byDay[day] ?? []
            let volume = dayRows.reduce(0.0) { $0 + $1.totalVolume }
            let rpes = dayRows.compactMap(\.avgRPE)
            let avgRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)
            let rpeStr = avgRPE.map { String(format: "RPE %.1f", $0) } ?? "RPE n/a"
            return "\(AIProgramPlanner.isoDay(day)): \(Int(volume))kg vol, \(rpeStr)"
        }
    }
}
