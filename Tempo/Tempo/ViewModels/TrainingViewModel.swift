//
// TrainingViewModel.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import AudioToolbox
import AVFoundation
import Foundation
import SwiftData
import SwiftUI
import UserNotifications

// MARK: - WorkoutSessionState

// Per STATE_MACHINES.md Section 1 — Workout Session state machine

enum WorkoutSessionState: Codable, Equatable {
    case idle
    case warmup(exerciseIndex: Int, warmupSetIndex: Int)
    case exercise(ExerciseSubState)
    case cooldown
    case summary
    case saved
    case paused(previousState: PausedFromState, pauseStartTime: Date)
    case interruptedCall(previousState: PausedFromState)
    case crashedRecovery
    case discarded

    enum ExerciseSubState: Codable, Equatable {
        case setActive(exerciseIndex: Int, setIndex: Int)
        case resting(exerciseIndex: Int, setIndex: Int, remainingSeconds: TimeInterval)
        case betweenExercises(fromIndex: Int, toIndex: Int)
    }

    enum PausedFromState: Codable, Equatable {
        case warmup(exerciseIndex: Int, warmupSetIndex: Int)
        case exercise(ExerciseSubState)
        case cooldown
    }

    var isActive: Bool {
        switch self {
        case .warmup,
             .exercise,
             .cooldown: true
        default: false
        }
    }
}

// MARK: - TrainingViewModel

// Per MODULE_TRAINING.md Sections 2, 9, 15 and BUILD_PLAN.md Step 9.2.
// Per STATE_MACHINES.md Section 1 — Workout Session state machine.

@Observable
@MainActor
final class TrainingViewModel {
    // MARK: - State

    var sessionState: WorkoutSessionState = .idle {
        didSet {
            #if DEBUG
                if oldValue != sessionState {
                    print("\(DebugTrace.prefix)[Workout] sessionState: \(oldValue) → \(sessionState) | exIdx=\(currentExerciseIndex) setIdx=\(currentSetIndex)")
                }
            #endif
        }
    }

    var todayPlan: WorkoutPlan?
    var weekPlans: [WorkoutPlan] = []
    var isLoading = true
    var isDeloadWeek = false

    /// AI rationale for this week's reconciled plan (Phase 2). Non-nil ONLY when
    /// the AI program ran and was reconciled against the floor — nil whenever
    /// the deterministic plan stands (offline, not Pro, no consent, failure).
    /// The Week Plan view shows it as a "why" line when present.
    var aiWeekRationale: String?

    /// Last week's graded outcome (Phase 4). Non-nil after the weekly review has
    /// run; drives the Coach Review card. nil before there's a full prior week.
    var lastWeekOutcome: WeekOutcome?

    /// Today's readiness-coach prescription (D2). The DailyReadinessCoach supersedes
    /// the legacy `checkForRecoveryAdjustment` loop: it runs every day across all
    /// modalities, applies the safety floor, and is the single daily card. nil
    /// until the coach has produced today's session.
    var dailySession: DailySession?

    // MARK: - Active Workout State

    var currentExerciseIndex: Int = 0
    var currentSetIndex: Int = 0
    var workoutStartTime: Date?
    var elapsedSeconds: TimeInterval = 0
    var totalPauseDuration: TimeInterval = 0
    var detectedPRs: [PersonalRecord] = []

    /// The working set just completed via `logSet`. The session view observes
    /// this to know which set the inline feedback panel edits.
    var lastCompletedSet: PlannedSet?

    /// SetFeedback row for the just-completed working set. Created eagerly in
    /// `logSet` with neutral defaults so a row always exists even if the user
    /// skips rest instantly; the inline feedback panel edits it in place
    /// (save-on-change), so nothing is lost when the rest timer auto-advances.
    /// Nil for warmup sets (no feedback collected on warmups).
    var currentFeedback: SetFeedback?

    /// User weight-unit preference, loaded from UserSettings in loadToday.
    /// All stored weights are kg; this is display-only conversion.
    var weightUnit: WeightUnit = .kg

    // MARK: - Non-Gym Activity (football / sprint / conditioning) confirm flow

    /// Drives the non-gym day card. Resolved by `loadNonGymActivity` from Whoop
    /// and from whether today's plan is already completed.
    enum NonGymActivityState: Equatable {
        case loading
        /// A Whoop activity tagged as this sport (e.g. soccer) was found.
        case foundTagged(WhoopActivitySummary)
        /// A Whoop activity exists for today but isn't tagged as this sport —
        /// ask "was this it?".
        case foundUntagged(WhoopActivitySummary)
        /// No Whoop activity today — offer manual attestation.
        case none
        /// User said the found activity wasn't this sport — stop prompting,
        /// but still allow a manual "I played" log.
        case dismissed
        /// Today's session was already confirmed + saved.
        case saved(WhoopActivitySummary?)
    }

    /// Plain value snapshot of a Whoop activity for display + save (avoids
    /// passing the Sendable struct around the view layer).
    struct WhoopActivitySummary: Equatable {
        let strain: Double
        let averageHeartRate: Double
        let durationMinutes: Double
        let caloriesBurned: Double
        let sportID: Int
        let startTime: Date
    }

    var nonGymActivityState: NonGymActivityState = .loading

    // MARK: - Rest Timer

    var restTimerRemaining: TimeInterval = 0
    var restTimerTotal: TimeInterval = 0
    var restTimerTask: Task<Void, Never>?
    /// Wall-clock instant the current rest period completes. The timer is
    /// anchored to this Date (not a per-tick decrement) so it stays correct
    /// when the app is backgrounded and the driving Task is suspended.
    var restEndDate: Date?
    /// Highest integer second for which a countdown cue has already fired,
    /// so re-syncing on foreground does not replay cues. Starts at Int.max.
    var lastCuedSecond = Int.max

    // MARK: - Guided Warm-Up

    /// Exercise IDs with a recent pain/injury note (Tier 2.3). Cached when the
    /// plan is populated / loaded so the session UI can show a caution without
    /// re-scanning every render. Empty when none.
    var painFlaggedExercises: Set<UUID> = []

    /// The resolved routine for today's workout, shown in the guided warm-up.
    var warmupRoutine: WarmupRoutine?
    /// Index of the move the user is currently on in the guided warm-up.
    var warmupMoveIndex: Int = 0
    /// Remaining seconds on the current TIMED warm-up move (0 for rep-based).
    var warmupMoveRemaining: TimeInterval = 0
    /// Wall-clock end instant for the current timed warm-up move — Date-anchored
    /// exactly like the rest timer so it survives backgrounding (the user walks
    /// around the gym during warm-up).
    var warmupMoveEndDate: Date?
    var warmupMoveTask: Task<Void, Never>?

    // MARK: - Elapsed Timer

    var elapsedTimerTask: Task<Void, Never>?

    // MARK: - Dependencies

    let trainingEngine: any TrainingEngineProtocol
    private let whoop: any WhoopServiceProtocol
    private let healthKit: any HealthKitServiceProtocol

    /// Optional network client for the AI training path (Phase 2). When nil
    /// (previews, tests, offline-only builds) the view model runs the pure
    /// deterministic engine — the AI upgrade is strictly additive and never a
    /// hard dependency. The deterministic plan is always the floor.
    let apiClient: APIClient?

    // MARK: - Init

    init(
        trainingEngine: any TrainingEngineProtocol,
        whoop: any WhoopServiceProtocol,
        healthKit: any HealthKitServiceProtocol,
        apiClient: APIClient? = nil
    ) {
        self.trainingEngine = trainingEngine
        self.whoop = whoop
        self.healthKit = healthKit
        self.apiClient = apiClient
    }

    // MARK: - Load Today's Workout

    func loadToday(modelContext: ModelContext) async {
        isLoading = true

        // Display unit for the session (weights are stored kg).
        if let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first {
            weightUnit = settings.weightUnit
        }

        // Source of truth: the Week Plan. Generate the whole week first so Today
        // and Week Plan can never disagree about what kind of workout today is.
        loadWeekPlan(modelContext: modelContext)

        // Resolve + persist today's plan. Shared with DailyResetCoordinator
        // so the Dashboard's Move quadrant (which only READS the persisted
        // row) always finds the same plan the Training tab shows — even if
        // the user opens the Dashboard before ever opening Training.
        let resolved = ensureTodayPlanPersisted(modelContext: modelContext)
        todayPlan = resolved.plan
        if resolved.isCrashedInProgress {
            sessionState = .crashedRecovery
        }

        // Tier 2.3 — refresh the pain-flag cache for the session UI (covers
        // plans that were already populated in a prior load, where
        // populateExercises didn't run this time).
        painFlaggedExercises = painFlaggedExerciseIDs(modelContext: modelContext)

        // Check deload week status (Phase 3: fatigue trend can trigger early).
        let deloadSettings = loadDeloadSettings(modelContext: modelContext)
        isDeloadWeek = trainingEngine.isDeloadWeek(
            date: Date(),
            deloadFrequencyWeeks: deloadSettings.frequency,
            trainingStartDate: deloadSettings.startDate,
            fatigueEWMA: adaptiveSignals(modelContext: modelContext).fatigueEWMA
        )

        isLoading = false

        // Phase 2 (TRAINING_INTELLIGENCE_TO_10.md) — AI hydration runs AFTER the
        // deterministic plan is already on screen. The floor renders first and
        // always stands; the AI is a strictly-additive upgrade that tunes volume
        // in place if (and only if) it's available, Pro-gated, and not yet run
        // this week. Failure is silent — the floor is the answer.
        await hydrateWeekWithAI(modelContext: modelContext)

        // D2 (INTELLIGENT_TRAINING_SYSTEM §5) — the daily readiness brain. SUPERSEDES
        // the legacy checkForRecoveryAdjustment loop: it runs every day across all
        // modalities, applies the deterministic safety floor on EVERY path, and is
        // the single daily card. Runs after hydration so it reads the reconciled
        // WorkoutPlan (§8: weekly owns the modality-default; daily adjusts within).
        await runDailyReadinessSession(modelContext: modelContext)

        // Phase 4 — grade last week once per ISO week and feed the result back
        // into the on-device profile (the macro self-correction loop). Also
        // populates the Coach Review card.
        runWeeklyOutcomeReview(modelContext: modelContext)
    }

    // MARK: - Weekly Outcome Review (Phase 4)

    /// Grade the previous week, apply the result to the AdaptiveProfile, and
    /// store the WeekOutcome for the Coach Review card. Runs once per ISO week —
    /// guarded by a PERSISTED key on AdaptiveProfile (not an in-memory var) so a
    /// cold start within the same week can't re-grade and COMPOUND applyOutcome
    /// against the persisted profile.
    func runWeeklyOutcomeReview(modelContext: ModelContext) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2
        let thisMonday = cal.date(from: comps) ?? Date()
        let weekKey = AIProgramPlanner.isoDay(thisMonday)

        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)
        guard profile.lastOutcomeReviewWeekKey != weekKey else { return }

        guard let lastMonday = cal.date(byAdding: .day, value: -7, to: thisMonday),
              let lastSunday = cal.date(byAdding: .day, value: -1, to: thisMonday) else { return }
        let lastWeekStart = cal.startOfDay(for: lastMonday)
        let lastWeekEnd = cal.startOfDay(for: lastSunday)

        // Last week's history rows.
        let lastWeekRows = (try? modelContext.fetch(FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.date >= lastWeekStart && $0.date <= lastWeekEnd }
        ))) ?? []

        // Need at least one logged session to grade anything.
        guard !lastWeekRows.isEmpty else {
            profile.lastOutcomeReviewWeekKey = weekKey
            try? modelContext.save()
            return
        }

        // Week-before tonnage for the trend.
        guard let priorStart = cal.date(byAdding: .day, value: -14, to: thisMonday),
              let priorEnd = cal.date(byAdding: .day, value: -8, to: thisMonday) else { return }
        let priorWeekStart = cal.startOfDay(for: priorStart)
        let priorWeekEnd = cal.startOfDay(for: priorEnd)
        let priorRows = (try? modelContext.fetch(FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.date >= priorWeekStart && $0.date <= priorWeekEnd }
        ))) ?? []
        let priorVolume = priorRows.reduce(0.0) { $0 + $1.totalVolume }

        // Planned training days last week = distinct non-rest gym days in the
        // current week template (a stable proxy for the cadence).
        let plannedTrainingDays = weekPlans.filter { $0.type.isGymWorkout }.count

        let outcome = TrainingOutcomeEvaluator.evaluate(
            lastWeek: lastWeekRows,
            plannedTrainingDays: max(plannedTrainingDays, 1),
            priorWeekVolume: priorVolume
        )

        // Feed the outcome back into the on-device profile (macro loop). Mark
        // the persisted guard in the SAME save so the apply happens exactly once.
        AdaptiveProfileUpdater.applyOutcome(outcome, to: profile)
        profile.lastOutcomeReviewWeekKey = weekKey
        try? modelContext.save()

        lastWeekOutcome = outcome
        #if DEBUG
            print("\(DebugTrace.prefix)[outcome] week graded: quality=\(String(format: "%.2f", outcome.qualityScore)) hits=\(outcome.progressionHits) overreach=\(outcome.overreachEvents) missed=\(outcome.missedSessions)")
        #endif
    }

    // MARK: - AI Week Hydration (Phase 2)

    /// Reconcile the deterministic week plan with an AI-proposed skeleton.
    /// No-ops when there's no API client (previews/tests/offline), when already
    /// run this week, or when a workout is in progress (never disturb a live
    /// session). All failures fall back to the deterministic plan silently.
    func hydrateWeekWithAI(modelContext: ModelContext) async {
        guard let apiClient else { return }
        guard !sessionState.isActive else { return }

        let cal = Calendar.current
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        comps.weekday = 2 // Monday
        let monday = cal.date(from: comps) ?? Date()
        let weekKey = AIProgramPlanner.isoDay(monday)

        // Once per ISO week (the Sonnet cost cap) — PERSISTED guard so a cold
        // start in the same week doesn't re-spend the call.
        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)
        guard profile.lastAIHydratedWeekKey != weekKey else { return }

        let footballDays = loadFootballDays(modelContext: modelContext)
        let recovery7Day = loadRecovery7DayTrend(modelContext: modelContext)
        let recentSessions = loadRecentSessionSummaries(modelContext: modelContext)

        let planner = AIProgramPlanner(api: apiClient)
        let result = await planner.planWeek(
            deterministicPlans: weekPlans,
            weekStart: monday,
            recovery7Day: recovery7Day,
            recentSessions: recentSessions,
            footballDays: AIProgramPlanner.footballDayNames(footballDays),
            // §14 Decision 1 — the weekly goal follows the declared block
            // emphasis; no block set → "hypertrophy", the pre-D3 literal.
            goal: (currentBlockEmphasis(modelContext: modelContext) ?? .physique).weeklyGoal
        )

        // Mark the week done regardless of whether AI ran — a 402 (not Pro / no
        // consent) or a network failure should NOT retrigger on every loadToday.
        profile.lastAIHydratedWeekKey = weekKey
        try? modelContext.save()

        // Only mutate state if AI actually produced a reconciled plan.
        if result.rationale != nil {
            weekPlans = result.plans
            aiWeekRationale = result.rationale
        }
    }

    /// Last-7-day recovery scores (oldest→newest) for the AI program prompt.
    private func loadRecovery7DayTrend(modelContext: ModelContext) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: today) else { return [] }
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= weekAgo },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.map { Int($0.recoveryScore.rounded()) }
    }

    // MARK: - Daily Readiness Session (D2 — the brain + floor)

    /// Once-daily: assemble today's ReadinessPicture from stored history, ask the
    /// DailyReadinessCoach (brain when eligible, deterministic+floor otherwise),
    /// persist the result as a DailySession linked 1:1 to today's WorkoutPlan, and
    /// resolve the plan's state (severe → mark .skipped/.floorForced). The floor
    /// runs on EVERY path (the coach guarantees produce-then-floor). Persisted
    /// once-daily guard caps it at ≤1 Haiku/day.
    func runDailyReadinessSession(modelContext: ModelContext) async {
        guard let apiClient else { return }
        guard !sessionState.isActive else { return }
        guard let plan = todayPlan else { return }

        // Once-per-day cap (PERSISTED — survives relaunch, hardens the cost cap).
        let todayKey = AIProgramPlanner.isoDay(Date())
        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)

        #if DEBUG
            // DEBUG test bypass: when set, ignore the once-daily guard so the daily
            // loop can be re-exercised without reinstalling. Clears itself after one
            // run. Set via Settings → Developer → "Force daily coach re-run".
            let forceRerun = UserDefaults.standard.bool(forKey: "tempo.debug.forceDailyRerun")
            if forceRerun {
                UserDefaults.standard.set(false, forKey: "tempo.debug.forceDailyRerun")
                // Delete today's stale session so the fresh one is the only row.
                if let stale = fetchTodayDailySession(modelContext: modelContext) {
                    modelContext.delete(stale)
                }
            }
        #else
            let forceRerun = false
        #endif

        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] enter forceRerun=\(forceRerun) alreadyRan=\(profile.lastDailySessionDayKey == todayKey)")
        #endif

        guard forceRerun || profile.lastDailySessionDayKey != todayKey else {
            // Already ran today — surface the persisted session for the card.
            dailySession = fetchTodayDailySession(modelContext: modelContext)
            #if DEBUG
                print("\(DebugTrace.prefix)[daily_coach] guard-skip (cached) — not re-calling today")
            #endif
            return
        }

        // 1. Assemble the picture from stored 30-day history (oldest→newest).
        let picture = assembleTodayPicture(modelContext: modelContext)

        // 2. brainEligible = DATA readiness only (≥30d history AND Whoop fresh).
        //    Entitlement (Pro/consent) is NOT checked here — the coach's 402→
        //    fallback owns that; duplicating risks the two disagreeing.
        let brainEligible = picture.hasBaselineForBrain && isWhoopFresh(modelContext: modelContext)

        // 3. Deterministic candidate (cold-start / offline / 402 / parse-fail
        //    fallback) built from the planned modality. Floor still applies to it.
        let candidate = deterministicCandidate(for: plan)

        // 4. Coach: produce-then-floor.
        let coach = DailyReadinessCoach(apiClient: apiClient)
        let result = await coach.session(
            for: picture,
            plannedModality: plan.type.rawValue,
            deterministicCandidate: candidate,
            brainEligible: brainEligible
        )

        // 5. Persist the DailySession 1:1 (every day — uniform link, §8 revised).
        let session = DailySession.from(
            decision: result.decision,
            date: Date(),
            source: result.source,
            workoutPlan: plan
        )
        modelContext.insert(session)

        // 6. Resolve the WorkoutPlan state. SEVERE → the planned day is superseded:
        //    mark .skipped with .floorForced so adherence does NOT penalize it
        //    (§8/§15.2 — body said recover, not a user flake).
        if result.decision.tier == .severe {
            plan.status = .skipped
            plan.skipReason = .floorForced
        }

        profile.lastDailySessionDayKey = todayKey
        try? modelContext.save()
        dailySession = session

        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] session persisted source=\(result.source.rawValue) tier=\(result.decision.tier.rawValue) modality=\(session.modality) planSkipped=\(result.decision.tier == .severe)")
        #endif
    }

    /// Assemble today's ReadinessPicture from the trailing-30-day DailyRecovery
    /// history (reuses the canonical forward-sorted fetch).
    private func assembleTodayPicture(modelContext: ModelContext) -> ReadinessPicture {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: -31, to: today) ?? today
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let snapshots = rows.map { r in
            DailyRecoverySnapshot(
                date: r.date, recoveryScore: r.recoveryScore, hrv: r.hrvRmssd,
                rhr: r.restingHR, respRate: r.respiratoryRate, sleepHours: r.sleepHours,
                sleepDebt: r.sleepDebt, strain: r.strain, deepSleepMin: r.deepSleepMin
            )
        }
        let todaySnapshot = snapshots.last(where: { cal.isDate($0.date, inSameDayAs: today) }) ?? snapshots.last

        // Body comp (latest snapshot) + today's check-in surface into the picture.
        let bodyComp = fetchLatestBodyComp(modelContext: modelContext)
        let checkIn = fetchTodayCheckIn(modelContext: modelContext)?.snapshot

        // D3 — days until the next COMPETITIVE match (distinct from recurring
        // football days). Feeds the brain's CONTEXT block + the T-1/T-0 prompt
        // lines, which are about TAPERING for a real game — a friendly scrimmage
        // doesn't drive that, so it's excluded here (matches the T-1 filter in
        // loadWeekPlan and the isCompetitive toggle's promise).
        let competitiveKickoffs = fetchUpcomingMatches(modelContext: modelContext)
            .filter(\.isCompetitive).map(\.kickoff)
        let daysUntilNextMatch = MatchSchedule.daysUntilNextMatch(kickoffs: competitiveKickoffs, from: Date())

        return ReadinessAssembler.assemble(
            history: snapshots,
            today: todaySnapshot,
            yesterdaySessions: [], // surfaced in a later enrichment (§13.2)
            bodyComp: bodyComp,
            checkIn: checkIn,
            daysUntilNextMatch: daysUntilNextMatch,
            blockEmphasis: currentBlockEmphasis(modelContext: modelContext),
            venueToday: venueTodaySnapshot(modelContext: modelContext)
        )
    }

    /// Today's venue context for the prompt (§16): the user's confirmed answer
    /// when present (highest quality), else the learned weekday pattern. nil
    /// when neither exists — the prompt stays silent (cold-start honesty).
    private func venueTodaySnapshot(modelContext: ModelContext) -> VenueTodaySnapshot? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)

        let pattern = ((try? modelContext.fetch(FetchDescriptor<VenuePattern>(
            predicate: #Predicate { $0.weekday == weekday }
        ))) ?? []).first

        let confirmation = ((try? modelContext.fetch(FetchDescriptor<VenueConfirmation>(
            predicate: #Predicate { $0.dayKey == today }
        ))) ?? []).first

        if let confirmation {
            return VenueTodaySnapshot(
                venueRaw: confirmation.venueRaw,
                startMin: confirmation.startMin,
                durationMin: pattern?.medianDurationMin,
                confirmed: true,
                assertsTime: true
            )
        }
        guard let pattern, let venueRaw = pattern.venueRaw else { return nil }
        return VenueTodaySnapshot(
            venueRaw: venueRaw,
            startMin: pattern.medianStartMin,
            durationMin: pattern.medianDurationMin,
            confirmed: false,
            assertsTime: pattern.sampleCount >= VenuePatternMath.minSamplesToAssertTime
                && pattern.medianStartMin != nil
        )
    }

    /// The declared training-block emphasis in force today (§14 Decision 1),
    /// or nil when no block covers today — callers default to .physique, the
    /// pre-D3 behavior. Latest-start-wins on overlap (TrainingBlockSchedule).
    private func currentBlockEmphasis(modelContext: ModelContext) -> BlockEmphasis? {
        let descriptor = FetchDescriptor<TrainingBlock>()
        let blocks = (try? modelContext.fetch(descriptor)) ?? []
        return TrainingBlockSchedule.currentEmphasis(spans: blocks.map(\.span), on: Date())
    }

    /// Kickoffs of all matches from today forward (start-of-day cutoff so a
    /// match earlier today still counts). Used for the readiness picture's
    /// daysUntilNextMatch and the deterministic week's T-1 leg-protection.
    private func fetchUpcomingMatches(modelContext: ModelContext) -> [Match] {
        let cutoff = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.kickoff >= cutoff },
            sortBy: [SortDescriptor(\.kickoff, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// A minimal deterministic session for the planned modality — the fallback
    /// when the brain is skipped or fails. Gym → pointer (engine fills loads);
    /// non-gym → an easy modality-appropriate block so cold-start/offline never
    /// empty-renders (§15.1/§15.4). The floor still clamps/vetoes this.
    private func deterministicCandidate(for plan: WorkoutPlan) -> DailySessionDTO {
        let type = plan.type
        let dur = plan.durationMinutes ?? 45
        let mk: (BlockKind, String?, String) -> SessionBlockDTO = { kind, split, label in
            SessionBlockDTO(kind: kind, label: label, notes: nil, cue: nil, scheduledMin: nil, split: split,
                            reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                            durationSec: nil, stroke: nil, runType: nil, paceSecPerKm: nil, sets: nil)
        }
        switch type {
        case .push, .pull, .legs, .upper, .lower, .fullBody:
            return DailySessionDTO(
                modality: type.rawValue, intensity: .moderate, durationMin: dur,
                blocks: [mk(.gym, type.rawValue, type.displayName)],
                shortWhy: "Today's planned \(type.displayName.lowercased()).", fullWhy: nil,
                expectedStrain: nil, expectedSessionRPE: nil
            )
        case .run:
            return DailySessionDTO(
                modality: "run", intensity: .easy, durationMin: dur,
                blocks: [SessionBlockDTO(kind: .run, label: "Easy run", notes: nil, cue: nil, scheduledMin: nil, split: nil,
                                         reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                                         durationSec: dur * 60, stroke: nil, runType: "tempo",
                                         paceSecPerKm: nil, sets: nil)],
                shortWhy: "Easy aerobic run.", fullWhy: nil, expectedStrain: nil, expectedSessionRPE: 4
            )
        case .football, .sprint, .conditioning:
            return DailySessionDTO(
                modality: type.rawValue, intensity: .moderate, durationMin: dur,
                blocks: [mk(.field, nil, type.displayName)],
                shortWhy: "Today's \(type.displayName.lowercased()).", fullWhy: nil,
                expectedStrain: nil, expectedSessionRPE: 5
            )
        case .mobility, .rest:
            return TrainingSafetyFloor.recoverySession(reason: "Recovery day.")
        }
    }

    private func isWhoopFresh(modelContext: ModelContext) -> Bool {
        // Fresh = a DailyRecovery row for today exists (§15.1: >48h stale → no brain).
        loadRecoveryScore(modelContext: modelContext) != nil
    }

    private func fetchTodayDailySession(modelContext: ModelContext) -> DailySession? {
        let today = Calendar.current.startOfDay(for: Date())
        let d = FetchDescriptor<DailySession>(predicate: #Predicate { $0.date == today })
        return try? modelContext.fetch(d).first
    }

    private func fetchLatestBodyComp(modelContext: ModelContext) -> BodyCompSnapshot? {
        var d = FetchDescriptor<BodyComposition>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return (try? modelContext.fetch(d))?.first?.snapshot
    }

    private func fetchTodayCheckIn(modelContext: ModelContext) -> MorningCheckIn? {
        let today = Calendar.current.startOfDay(for: Date())
        let d = FetchDescriptor<MorningCheckIn>(predicate: #Predicate { $0.date == today })
        return try? modelContext.fetch(d).first
    }

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
    private func applyErrorFitCorrection(planID: UUID, modelContext: ModelContext) {
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

    /// Fetch the single AdaptiveProfile, creating it on first use.
    private func fetchOrCreateAdaptiveProfile(modelContext: ModelContext) -> AdaptiveProfile {
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
    private func updateAdaptiveProfile(with session: [ExerciseHistory], modelContext: ModelContext) {
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

    /// Map a recoveryAdjustment multiplier back to a representative recovery
    /// score for the adjustment prompt (inverse of the engine's zone cuts).
    

    /// Short summaries of the last 4 completed sessions for the AI prompt.
    private func loadRecentSessionSummaries(modelContext: ModelContext) -> [String] {
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

    /// Result of resolving today's plan — the persisted WorkoutPlan plus
    /// whether it's a crashed in-progress session the caller must restore.
    struct ResolvedTodayPlan {
        let plan: WorkoutPlan
        let isCrashedInProgress: Bool
    }

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
        templateType: WorkoutType
    ) -> PlanResolution {
        switch existingStatus {
        case .planned:
            return existingType == templateType ? .keep : .replace
        default:
            // completed / inProgress / skipped — sacred, never replace.
            return .keep
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
                   templateType: canonical.type
               ) == .replace {
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
            split: split
        )
        populateExercises(for: plan, modelContext: modelContext)
        modelContext.insert(plan)
        try? modelContext.save()
        return ResolvedTodayPlan(plan: plan, isCrashedInProgress: false)
    }

    // MARK: - Load Week Plan

    func loadWeekPlan(modelContext: ModelContext) {
        let cal = Calendar.current
        let today = Date()

        // Find Monday of this week
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps.weekday = 2 // Monday
        let monday = cal.date(from: comps) ?? today

        let footballDays = loadFootballDays(modelContext: modelContext)
        let split = loadTrainingSplit(modelContext: modelContext)
        let recoveryScores = loadRecoveryScores(modelContext: modelContext, startDate: monday)
        // Phase 3: per-user learned recovery-threshold offset (clamped ±10).
        let signals = adaptiveSignals(modelContext: modelContext)
        // D3 — dated matches re-shape the surrounding days (T-0/T-1) on top of
        // the recurring football weekdays. Free deterministic re-periodization.
        // ALL matches are a T-0 session day (you're playing either way); only
        // COMPETITIVE ones drive T-1 taper (no heavy legs) — a friendly scrimmage
        // doesn't warrant tapering, honouring the isCompetitive toggle.
        let upcomingMatches = fetchUpcomingMatches(modelContext: modelContext)
        let matchDayKeys = Set(upcomingMatches.map { cal.startOfDay(for: $0.kickoff) })
        let competitiveMatchDayKeys = Set(upcomingMatches
            .filter(\.isCompetitive).map { cal.startOfDay(for: $0.kickoff) })

        weekPlans = trainingEngine.generateWeekPlan(
            startDate: monday,
            recoveryScores: recoveryScores,
            footballDays: footballDays,
            split: split,
            recoveryThresholdOffset: signals.thresholdOffset,
            matchDayKeys: matchDayKeys,
            competitiveMatchDayKeys: competitiveMatchDayKeys
        )

        // Check deload week status (Phase 3: fatigue trend can trigger early).
        let deloadSettings = loadDeloadSettings(modelContext: modelContext)
        isDeloadWeek = trainingEngine.isDeloadWeek(
            date: Date(),
            deloadFrequencyWeeks: deloadSettings.frequency,
            trainingStartDate: deloadSettings.startDate,
            fatigueEWMA: signals.fatigueEWMA
        )

        // Populate exercises for each gym workout
        for plan in weekPlans {
            populateExercises(for: plan, modelContext: modelContext)
        }
    }

    /// Re-personalize the week after a schedule-input edit (football days /
    /// split). Future days are ephemeral and regenerate from the new inputs;
    /// today is re-resolved under the sacredness guard (planResolution) so a
    /// completed/in-progress session is never disturbed. Posts
    /// `.tempoWorkoutChanged` so the Dashboard Move quadrant + Today view refresh.
    func repersonalizeSchedule(modelContext: ModelContext) {
        // Rebuild the forward-looking week from the new UserSettings inputs.
        loadWeekPlan(modelContext: modelContext)
        // Re-resolve today: replaces a still-.planned today row whose type now
        // disagrees with the new template; keeps completed/in-progress (sacred).
        let resolved = ensureTodayPlanPersisted(modelContext: modelContext)
        todayPlan = resolved.plan
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    // MARK: - Start Workout

    // Per STATE_MACHINES.md Section 1 — idle → warmup/exercise

    func startWorkout() {
        guard sessionState == .idle || sessionState == .crashedRecovery else {
            return
        }
        guard let plan = todayPlan else {
            return
        }

        plan.status = .inProgress
        elapsedSeconds = 0
        totalPauseDuration = 0
        currentExerciseIndex = 0
        currentSetIndex = 0
        detectedPRs = []

        // Always enter the warmup state for a gym workout so the guided
        // workout-specific warm-up + mobility block (WarmupRoutine) is shown
        // before the first working set — independent of whether the first
        // exercise carries ramp sets. advancePastWarmup handles the
        // no-ramp-set case (firstWorkingIndex = 0). Non-gym types never reach
        // startWorkout's gym flow.
        if plan.type.isGymWorkout {
            // Resolve the guided warm-up routine and start at the first move.
            // Do NOT stamp startedAt / workoutStartTime yet — the session clock
            // (and the persisted start time, incl. on crash recovery) begins at
            // the first WORKING set so warm-up is not counted as duration. Both
            // are set in advancePastWarmup.
            warmupRoutine = WarmupRoutine.routine(for: plan.type)
            warmupMoveIndex = 0
            // Activate the audio session ONCE for the whole warm-up so cues
            // duck music without re-ducking on every move transition.
            Self.activateRestAudioSession()
            sessionState = .warmup(exerciseIndex: 0, warmupSetIndex: 0)
            startWarmupMoveTimerForCurrent()
        } else {
            plan.startedAt = Date()
            workoutStartTime = Date()
            sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))
            // Non-gym sessions have no warm-up block — start the clock now.
            startElapsedTimer()
        }
        // Move quadrant should flip planned → in-progress on the Dashboard.
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    // MARK: - Advance Past Warmup

    // Per STATE_MACHINES.md §1 line 158 — warmup → exercise.setActive once
    // the user taps "Ready — Start Working Sets". Warmup sets are display-only
    // guidance (info-screen-then-skip): we jump to the first non-warmup set so
    // warmup is never logged and never counts toward volume/history.

    func advancePastWarmup() {
        guard case .warmup = sessionState, let plan = todayPlan else {
            return
        }
        stopWarmupMoveTimer()
        let exercises = plan.orderedExercises
        guard let first = exercises.first else {
            sessionState = .cooldown
            return
        }
        let sets = first.orderedSets
        let firstWorkingIndex = sets.firstIndex { !$0.isWarmup } ?? 0
        #if DEBUG
            print("\(DebugTrace.prefix)[Workout] advancePastWarmup: totalSets=\(sets.count) warmups=\(sets.filter(\.isWarmup).count) → firstWorkingIndex=\(firstWorkingIndex)")
        #endif
        currentExerciseIndex = 0
        currentSetIndex = firstWorkingIndex
        // Record warm-up as completed only if the user actually worked through
        // all the moves (not if they hit "Skip whole warm-up").
        let moveCount = warmupRoutine?.moves.count ?? 0
        plan.warmupCompleted = moveCount > 0 && warmupMoveIndex >= moveCount
        // Clock starts here — warm-up time is NOT counted in session duration.
        // Stamp plan.startedAt here too (not at warmup entry) so the persisted
        // start time and crash-recovery elapsed math both exclude warm-up.
        let now = Date()
        todayPlan?.startedAt = now
        workoutStartTime = now
        elapsedSeconds = 0
        totalPauseDuration = 0
        startElapsedTimer()
        sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: firstWorkingIndex))
    }

    // MARK: - Resume from Crash Recovery

    func resumeFromCrash() {
        guard sessionState == .crashedRecovery, let plan = todayPlan else {
            return
        }

        // Restore state from plan
        if let startedAt = plan.startedAt {
            workoutStartTime = startedAt
            // Approximate elapsed time
            elapsedSeconds = Date().timeIntervalSince(startedAt)
        }

        // Find current position
        let exercises = plan.orderedExercises
        var foundActiveExercise = false
        for (exIdx, ex) in exercises.enumerated() {
            if !ex.isComplete {
                let completedSetsCount = (ex.sets ?? []).filter(\.completed).count
                currentExerciseIndex = exIdx
                currentSetIndex = completedSetsCount
                sessionState = .exercise(.setActive(exerciseIndex: exIdx, setIndex: completedSetsCount))
                foundActiveExercise = true
                break
            }
        }

        if !foundActiveExercise {
            sessionState = .cooldown
        }

        startElapsedTimer()
    }

    // MARK: - Discard Crashed Workout

    func discardCrashedWorkout(modelContext: ModelContext) {
        guard sessionState == .crashedRecovery else {
            return
        }
        if let plan = todayPlan {
            plan.status = .skipped
        }
        try? modelContext.save()
        sessionState = .discarded
        resetState()
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    // MARK: - Log Set

    // Per STATE_MACHINES.md — exercise.setActive → exercise.resting

    func logSet(
        weight: Double,
        reps: Int,
        modelContext: ModelContext
    ) {
        guard let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return
        }

        let plannedExercise = exercises[currentExerciseIndex]
        let sets = plannedExercise.orderedSets

        guard currentSetIndex < sets.count else {
            return
        }

        let set = sets[currentSetIndex]
        set.actualWeight = weight
        set.actualReps = reps
        set.completed = true
        set.completedAt = Date()

        // Surface the just-completed set so the session view's inline feedback
        // panel edits exactly this set.
        lastCompletedSet = set

        // Eagerly create the feedback row for WORKING sets with neutral
        // defaults. RPE is collected end-of-set only (no set-active prompt),
        // and the inline panel edits this row save-on-change — so even an
        // instant "Skip Rest" leaves a persisted, sensible record.
        if set.isWarmup {
            currentFeedback = nil
        } else {
            let feedback = SetFeedback(plannedSet: set, rpe: 7)
            modelContext.insert(feedback)
            set.rpe = feedback.rpe
            currentFeedback = feedback
        }

        // Persist immediately (crash recovery)
        try? modelContext.save()

        // PR detection — working sets only. Warmup ramp sets must never trigger
        // a PR (this is why duplicate/low PRs appeared, e.g. two "Face Pull" PRs:
        // the warmup set and the working set each fired).
        if !set.isWarmup, let exercise = plannedExercise.exercise {
            if let pr = trainingEngine.detectPersonalRecord(
                exercise: exercise,
                weight: weight,
                reps: reps
            ) {
                modelContext.insert(pr)
                try? modelContext.save()
                detectedPRs.append(pr)
                HapticManager.notification(.success)
            }
        }

        // Determine next state
        let isLastSet = currentSetIndex >= sets.count - 1
        let isLastExercise = currentExerciseIndex >= exercises.count - 1
        #if DEBUG
            let warmupCount = sets.filter(\.isWarmup).count
            print("\(DebugTrace.prefix)[Workout] logSet: exIdx=\(currentExerciseIndex)/\(exercises.count) setIdx=\(currentSetIndex)/\(sets.count) (warmups=\(warmupCount)) → isLastSet=\(isLastSet) isLastExercise=\(isLastExercise)")
        #endif

        if isLastSet, isLastExercise {
            // Workout complete → straight to summary (cooldown screen removed;
            // the last set's feedback is editable at the top of the summary).
            stopElapsedTimer()
            sessionState = .summary
        } else if isLastSet {
            // Per STATE_MACHINES.md — between exercises
            let restDuration = restDuration(for: plannedExercise)
            startRestTimer(duration: restDuration, nextAction: .nextExercise)
            sessionState = .exercise(.resting(
                exerciseIndex: currentExerciseIndex,
                setIndex: currentSetIndex,
                remainingSeconds: restDuration
            ))
        } else {
            // Per STATE_MACHINES.md — rest between sets
            let restDuration = restDuration(for: plannedExercise)
            startRestTimer(duration: restDuration, nextAction: .nextSet)
            sessionState = .exercise(.resting(
                exerciseIndex: currentExerciseIndex,
                setIndex: currentSetIndex,
                remainingSeconds: restDuration
            ))
        }
    }

    /// Write-through update for the inline set-feedback panel. Every field
    /// change persists immediately so the record survives the rest timer
    /// auto-advancing or the user skipping rest. Mirrors RPE onto the set so
    /// engine/history code that reads `PlannedSet.rpe` stays consistent.
    func updateFeedback(
        rpe: Int? = nil,
        breath: BreathDifficulty? = nil,
        form: FormQuality? = nil,
        note: String? = nil,
        modelContext: ModelContext
    ) {
        guard let feedback = currentFeedback else {
            return
        }
        // Any call here means the user actually interacted with the inline
        // feedback panel — mark it real signal so Tier-2 aggregation counts it
        // (eager-created defaults stay userProvidedFeedback=false).
        feedback.userProvidedFeedback = true
        if let rpe {
            feedback.rpe = max(1, min(10, rpe))
            lastCompletedSet?.rpe = feedback.rpe
        }
        if let breath {
            feedback.breathDifficulty = breath
        }
        if let form {
            feedback.formQuality = form
        }
        if let note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            feedback.note = trimmed.isEmpty ? nil : trimmed
        }
        try? modelContext.save()

        // If the workout is ALREADY persisted (the last set's feedback is now
        // edited in the summary, after persistCompletion ran on .summary entry),
        // recompute that exercise's ExerciseHistory aggregate so the edit isn't
        // silently dropped from the Tier-2 signal.
        if todayPlan?.status == .completed {
            recomputeHistoryAggregate(for: lastCompletedSet?.plannedExercise, modelContext: modelContext)
        }
    }

    /// Recompute one exercise's persisted ExerciseHistory feedback aggregate
    /// from the latest user-provided SetFeedback. Used when the last set's
    /// feedback is entered in the summary, after the history row was already
    /// written on .summary entry.
    private func recomputeHistoryAggregate(for plannedExercise: PlannedExercise?, modelContext: ModelContext) {
        guard let plannedExercise,
              let exercise = plannedExercise.exercise,
              let planID = todayPlan?.id
        else {
            return
        }
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate<ExerciseHistory> { $0.workoutPlanID == planID }
        )
        guard let rows = try? modelContext.fetch(descriptor) else {
            return
        }
        guard let row = rows.first(where: { $0.exercise?.id == exerciseID }) else {
            return
        }
        let completedSets = (plannedExercise.sets ?? []).filter { $0.completed && !$0.isWarmup }
        let fbDescriptor = FetchDescriptor<SetFeedback>(
            predicate: #Predicate<SetFeedback> { $0.userProvidedFeedback }
        )
        let entered = Dictionary(
            ((try? modelContext.fetch(fbDescriptor)) ?? []).map { ($0.setID, $0) }
        ) { first, _ in first }
        let agg = Self.aggregateFeedback(completedSets: completedSets, enteredFeedback: entered)
        row.avgRPE = agg.avgRPE
        row.worstFormRaw = agg.worstFormRaw
        row.feedbackSampleCount = agg.count
        row.gassedFraction = agg.gassedFraction
        try? modelContext.save()
    }

    // MARK: - Skip Rest

    func skipRest() {
        stopRestTimer()
        advanceAfterRest()
    }

    // MARK: - Advance After Rest

    enum RestNextAction {
        case nextSet
        case nextExercise
    }

    var pendingRestAction: RestNextAction = .nextSet

    func advanceAfterRest() {
        guard let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises

        switch pendingRestAction {
        case .nextSet:
            currentSetIndex += 1
            sessionState = .exercise(.setActive(
                exerciseIndex: currentExerciseIndex,
                setIndex: currentSetIndex
            ))
            HapticManager.notification(.warning) // rest complete haptic
        case .nextExercise:
            let nextIndex = currentExerciseIndex + 1
            if nextIndex < exercises.count {
                sessionState = .exercise(.betweenExercises(
                    fromIndex: currentExerciseIndex,
                    toIndex: nextIndex
                ))
                // Short delay for transition animation, then advance
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    currentExerciseIndex = nextIndex
                    currentSetIndex = 0
                    sessionState = .exercise(.setActive(
                        exerciseIndex: nextIndex,
                        setIndex: 0
                    ))
                }
            } else {
                // Workout complete after the last inter-exercise rest.
                stopElapsedTimer()
                sessionState = .summary
            }
            HapticManager.notification(.warning)
        }
    }

    // MARK: - Finish Workout (manual)

    // Per STATE_MACHINES.md — any active state → cooldown → summary

    /// Finish the session early (user tapped Finish before all sets). Saving is
    /// the caller's choice — see `discardActiveWorkout`. This path goes straight
    /// to the summary (no cooldown screen); persistCompletion (fired on .summary
    /// entry by the tab) saves only the working sets actually logged.
    func finishWorkout() {
        stopRestTimer()
        stopWarmupMoveTimer()
        stopElapsedTimer()
        sessionState = .summary
    }

    /// Discard the in-progress session: mark the day skipped, drop any sets
    /// logged this session WITHOUT writing ExerciseHistory, and reset. The day
    /// stays open to redo. Used by the Finish → "Discard" choice.
    func discardActiveWorkout(modelContext: ModelContext) {
        // Allow discard from any live state (active / paused / cooldown).
        switch sessionState {
        case .warmup, .exercise, .cooldown, .paused:
            break
        default:
            return
        }
        stopRestTimer()
        stopWarmupMoveTimer()
        stopElapsedTimer()
        if let plan = todayPlan {
            // Roll back this session's logged sets so a re-do starts clean.
            // Keep the plan .planned (NOT .skipped/.completed) so the day stays
            // OPEN TO REDO, exactly as the dialog promises — and writes no
            // ExerciseHistory.
            for ex in plan.orderedExercises {
                for set in ex.orderedSets where set.completed {
                    set.completed = false
                    set.actualWeight = nil
                    set.actualReps = nil
                    set.completedAt = nil
                }
            }
            plan.status = .planned
            plan.startedAt = nil
        }
        try? modelContext.save()
        currentFeedback = nil
        lastCompletedSet = nil
        detectedPRs = []
        // Momentary .discarded so TrainingTabView dismisses the cover, then it
        // reloads today and the state settles back to .idle (ready to restart).
        sessionState = .discarded
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    // MARK: - Save Workout

    // Per STATE_MACHINES.md — summary → saved

    /// Persist the completed workout: flip status to `.completed` and write one
    /// ExerciseHistory row per exercise that had a completed working set.
    ///
    /// IDEMPOTENT — safe to call more than once for the same plan. This is the
    /// crux of the data-loss fix: completion is persisted as soon as the
    /// session reaches `.summary` (auto, not button-gated), AND the SAVE button
    /// still calls it; the guard + dedup make the second call a no-op instead
    /// of doubling history rows. Returns true if it wrote (first call), false
    /// if it was already persisted.
    @discardableResult
    func persistCompletion(modelContext: ModelContext) -> Bool {
        guard let plan = todayPlan else {
            return false
        }
        // Already persisted (e.g. auto-save on .summary entry ran, now the
        // SAVE button fires). Don't write twice.
        guard plan.status != .completed else {
            return false
        }

        let planID = plan.id

        // Per build done_when #11 — write one ExerciseHistory record per
        // exercise that had at least one completed working set. Warmup sets
        // are excluded (they are never marked completed). This is the trend
        // signal future workout generation reads.
        //
        // SNAPSHOT the relationship data into plain value structs BEFORE
        // we mutate the context. Iterating plan.orderedExercises +
        // dereferencing .sets while mutating the same context is the
        // SwiftData-invalidation pattern that crashed nutrition 3×. Reading
        // everything up-front means no live relationship is touched during
        // the insert loop.
        //
        // CRUCIAL: compute snapshots BEFORE flipping status. A session with
        // zero completed working sets is NOT a completed workout — auto-save
        // now fires on every .summary entry (incl. an early "Finish" tap or
        // the instant-finish bug), and Step 1 makes a .completed plan sacred.
        // Flipping status with no sets would mint a phantom completed plan
        // that can never be regenerated, locking the day. Guard against it.
        // Up-front map of USER-PROVIDED feedback by setID (eager-default rows
        // with userProvidedFeedback==false are excluded — they are not signal).
        // Built before the snapshot loop so no live relationship is touched mid-
        // mutation (the SwiftData-invalidation discipline above).
        let enteredFeedback: [UUID: SetFeedback] = {
            let descriptor = FetchDescriptor<SetFeedback>(
                predicate: #Predicate<SetFeedback> { $0.userProvidedFeedback }
            )
            let rows = (try? modelContext.fetch(descriptor)) ?? []
            return Dictionary(rows.map { ($0.setID, $0) }) { first, _ in first }
        }()

        struct HistorySnapshot {
            let exercise: Exercise
            let totalVolume: Double
            let best1RM: Double?
            let bestSetWeight: Double?
            let bestSetReps: Int?
            let setsPerformed: Int
            let avgRPE: Double?
            let worstFormRaw: String?
            let feedbackSampleCount: Int
            let gassedFraction: Double?
        }
        let snapshots: [HistorySnapshot] = plan.orderedExercises.compactMap { plannedEx in
            guard let exercise = plannedEx.exercise else { return nil }
            let completedSets = (plannedEx.sets ?? []).filter { $0.completed && !$0.isWarmup }
            guard !completedSets.isEmpty else { return nil }
            let totalVolume = completedSets.reduce(0.0) { acc, set in
                guard let w = set.actualWeight, let r = set.actualReps else { return acc }
                return acc + (w * Double(r))
            }
            let best = completedSets.max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) }

            // Aggregate ONLY user-provided feedback for this exercise's working
            // sets (pure helper, unit-tested). No entered feedback → nil/0.
            let agg = Self.aggregateFeedback(completedSets: completedSets, enteredFeedback: enteredFeedback)

            return HistorySnapshot(
                exercise: exercise,
                totalVolume: totalVolume,
                best1RM: completedSets.compactMap(\.estimated1RM).max(),
                bestSetWeight: best?.actualWeight,
                bestSetReps: best?.actualReps,
                setsPerformed: completedSets.count,
                avgRPE: agg.avgRPE,
                worstFormRaw: agg.worstFormRaw,
                feedbackSampleCount: agg.count,
                gassedFraction: agg.gassedFraction
            )
        }

        guard !snapshots.isEmpty else {
            // Nothing was actually logged — do NOT mark the plan completed.
            // Leave it .planned/.inProgress so the day stays open.
            #if DEBUG
                print("\(DebugTrace.prefix)[Workout] persistCompletion: plan=\(planID) NO completed working sets — not marking complete")
            #endif
            return false
        }

        plan.status = .completed
        plan.finishedAt = Date()
        plan.durationMinutes = Int(elapsedSeconds / 60)
        let sessionDate = plan.finishedAt ?? Date()

        // Defensive: if any ExerciseHistory already carries this plan's ID
        // (a prior partial/duplicate write), remove it before re-inserting so
        // the store can never accumulate duplicate rows for one session.
        let staleDescriptor = FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate<ExerciseHistory> { $0.workoutPlanID == planID }
        )
        if let stale = try? modelContext.fetch(staleDescriptor) {
            for row in stale {
                modelContext.delete(row)
            }
        }
        for snap in snapshots {
            let history = ExerciseHistory(
                date: sessionDate,
                estimated1RM: snap.best1RM,
                totalVolume: snap.totalVolume,
                bestSetWeight: snap.bestSetWeight,
                bestSetReps: snap.bestSetReps,
                setsPerformed: snap.setsPerformed,
                avgRPE: snap.avgRPE,
                worstFormRaw: snap.worstFormRaw,
                feedbackSampleCount: snap.feedbackSampleCount,
                gassedFraction: snap.gassedFraction,
                workoutPlanID: planID,
                exercise: snap.exercise
            )
            modelContext.insert(history)
        }

        // Step 1 (measurement spine) — backfill the outcome onto the
        // PredictionLog rows written at prescribe time, so each prediction now
        // sits next to what actually happened. This is the prediction↔reality
        // pair Step 2's error metric reads. Matched by (planID, exerciseID) —
        // the same key the prediction was written under.
        let outcomes: [PredictionOutcome] = snapshots.map { snap in
            PredictionOutcome(
                exerciseID: snap.exercise.id,
                bestSetReps: snap.bestSetReps,
                avgRPE: snap.avgRPE,
                worstFormRaw: snap.worstFormRaw,
                bestSetWeight: snap.bestSetWeight
            )
        }
        backfillPredictionOutcomes(planID: planID, outcomes: outcomes, modelContext: modelContext)

        // Step 3 (measure → correct) — fit the learned increments to the MEASURED
        // RPE error from the predictions just resolved, instead of the blind
        // RPE-bucket nudge. Conservative partial step, clamped. This is the first
        // place the engine consumes its own accuracy signal to change behavior.
        applyErrorFitCorrection(planID: planID, modelContext: modelContext)

        // §16.2 — a completed session is venue-pattern evidence (start time,
        // duration, inferred venue, completion). Cheap pure recompute.
        VenuePatternLearner.recompute(modelContext: modelContext)

        // Persist to SwiftData
        try? modelContext.save()
        #if DEBUG
            print("\(DebugTrace.prefix)[Workout] persistCompletion: plan=\(planID) wrote \(snapshots.count) history rows, status=.completed")
        #endif

        // Phase 3 (TRAINING_INTELLIGENCE_TO_10.md Fix 3.2) — feed the session
        // into the on-device AdaptiveProfile so the engine learns THIS user's
        // increments / recovery tolerance / fatigue trend over time. Bounded
        // online updates; the deterministic floor is unaffected.
        let sessionRows = snapshots.map { snap in
            ExerciseHistory(
                date: sessionDate,
                avgRPE: snap.avgRPE,
                worstFormRaw: snap.worstFormRaw,
                feedbackSampleCount: snap.feedbackSampleCount,
                exercise: snap.exercise
            )
        }
        updateAdaptiveProfile(with: sessionRows, modelContext: modelContext)

        // Day-plan engine signal — a logged workout means subsequent
        // blocks (especially recovery + meals) may shift. DayPlanScheduler
        // debounces the cascade.
        NotificationCenter.default.post(
            name: .tempoDayPlanReplanRequested,
            object: nil,
            userInfo: ["reason": DayPlanReason.workoutLogged.rawValue]
        )
        // Keep the Dashboard Move quadrant in sync with the just-completed
        // workout (status flipped to .completed above).
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        return true
    }

    func saveWorkout(modelContext: ModelContext) async {
        // Completion may already be persisted (auto-saved on entering
        // .summary). This call is idempotent; it writes only if it hasn't yet.
        persistCompletion(modelContext: modelContext)

        // Write to HealthKit (via step 5.7) — best-effort, Phase 5.

        sessionState = .saved
        resetState()
    }

    // MARK: - Non-Gym Completion (football / sprint / conditioning)

    /// Mark today's NON-GYM training day complete and save a permanent
    /// `ActivitySession` record. This is the deliberate sibling of
    /// `persistCompletion` — non-gym days have zero working sets, so they must
    /// NOT route through the gym path (whose `guard !snapshots.isEmpty` would
    /// refuse to complete them). Idempotent: a second call is a no-op.
    ///
    /// `whoop` carries the confirmed Whoop activity (branches a/b); pass nil
    /// for a manual attestation with no Whoop data (branch c). `sportID`
    /// preserves the original Whoop sport id even when the user re-labels an
    /// untagged activity as football, so the saved data stays honest.
    @discardableResult
    func persistNonGymCompletion(
        whoop: WhoopWorkoutData?,
        modelContext: ModelContext
    ) -> Bool {
        guard let plan = todayPlan else {
            return false
        }
        guard plan.status != .completed else {
            return false // already saved — don't write twice
        }

        let planID = plan.id

        // Dedup: drop any ActivitySession already tied to this plan before
        // inserting, so one plan maps to exactly one session (mirrors the
        // stale-row cleanup in persistCompletion).
        let staleDescriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate<ActivitySession> { $0.workoutPlanID == planID }
        )
        if let stale = try? modelContext.fetch(staleDescriptor) {
            for row in stale {
                modelContext.delete(row)
            }
        }

        let session = ActivitySession(
            date: Date(),
            startTime: whoop?.startTime ?? Date(),
            workoutType: plan.type.rawValue,
            sportID: whoop?.sportID ?? -1,
            source: whoop == nil ? "manual" : "whoop",
            workoutPlanID: planID,
            strain: whoop?.strain,
            averageHeartRate: whoop?.averageHeartRate,
            maxHeartRate: whoop?.maxHeartRate,
            caloriesBurned: whoop?.caloriesBurned,
            durationMinutes: whoop?.durationMinutes
        )
        modelContext.insert(session)

        plan.status = .completed
        plan.finishedAt = Date()
        if let mins = whoop?.durationMinutes {
            plan.durationMinutes = Int(mins)
        }

        try? modelContext.save()

        // §16.2 — non-gym completions are venue-pattern evidence too.
        VenuePatternLearner.recompute(modelContext: modelContext)

        #if DEBUG
            print("\(DebugTrace.prefix)[Workout] persistNonGymCompletion: plan=\(planID) type=\(plan.type.rawValue) source=\(session.source) strain=\(session.strain.map { String($0) } ?? "nil")")
        #endif

        // Same cross-surface signals as the gym path — without these the
        // Dashboard Move quadrant and the day-plan / recovery cascade won't
        // react to the completed non-gym session.
        NotificationCenter.default.post(
            name: .tempoDayPlanReplanRequested,
            object: nil,
            userInfo: ["reason": DayPlanReason.workoutLogged.rawValue]
        )
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        return true
    }

    /// Resolve the non-gym day card state. If today's plan is already completed,
    /// surface the saved summary; otherwise fetch today's Whoop activities and
    /// branch tagged / untagged / none. Call from the card's `.task`.
    func loadNonGymActivity(modelContext: ModelContext) async {
        guard let plan = todayPlan else {
            nonGymActivityState = .none
            return
        }

        // Already saved — show the persisted summary, never re-prompt.
        if plan.status == .completed {
            let planID = plan.id
            let descriptor = FetchDescriptor<ActivitySession>(
                predicate: #Predicate<ActivitySession> { $0.workoutPlanID == planID }
            )
            let saved = (try? modelContext.fetch(descriptor))?.first
            nonGymActivityState = .saved(saved.flatMap(Self.summary(from:)))
            return
        }

        nonGymActivityState = .loading

        // Whoop sport id for the plan's type (soccer == 1). Used to recognise a
        // tagged match; everything else is "untagged".
        let expectedSportID = Self.whoopSportID(for: plan.type)

        let activities = (try? await whoop.fetchWorkouts(for: Date())) ?? []
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todays = activities.filter { cal.isDate($0.startTime, inSameDayAs: todayStart) }

        let tagged = todays.filter { $0.sportID == expectedSportID }
        if !tagged.isEmpty {
            // Sum ALL matching sessions for the day — two football sessions
            // must not silently drop one. Strain/calories/duration aggregate;
            // avg HR is duration-weighted; startTime is the earliest.
            nonGymActivityState = .foundTagged(Self.aggregate(tagged))
        } else if let any = todays.max(by: { $0.strain < $1.strain }) {
            // Untagged is ambiguous — don't sum unrelated activities. Show the
            // single highest-strain one and let the user confirm or reject it.
            nonGymActivityState = .foundUntagged(Self.summary(from: any))
        } else {
            nonGymActivityState = .none
        }
    }

    /// Combine multiple same-day activities into one summary so no session is
    /// lost. Strain / calories / duration sum; avg HR is duration-weighted;
    /// sportID + startTime come from the earliest session.
    private static func aggregate(_ items: [WhoopWorkoutData]) -> WhoopActivitySummary {
        let totalStrain = items.reduce(0) { $0 + $1.strain }
        let totalCal = items.reduce(0) { $0 + $1.caloriesBurned }
        let totalMin = items.reduce(0) { $0 + $1.durationMinutes }
        let hrNumerator = items.reduce(0) { $0 + $1.averageHeartRate * $1.durationMinutes }
        let avgHR = totalMin > 0 ? hrNumerator / totalMin : (items.first?.averageHeartRate ?? 0)
        let earliest = items.min { $0.startTime < $1.startTime }
        return WhoopActivitySummary(
            strain: totalStrain,
            averageHeartRate: avgHR,
            durationMinutes: totalMin,
            caloriesBurned: totalCal,
            sportID: earliest?.sportID ?? items.first?.sportID ?? -1,
            startTime: earliest?.startTime ?? Date()
        )
    }

    /// Confirm the non-gym session and persist it. `summary` is the Whoop
    /// activity to attach, or nil for a manual "I did it" with no Whoop data.
    func confirmNonGymActivity(
        _ summary: WhoopActivitySummary?,
        modelContext: ModelContext
    ) {
        let whoopData: WhoopWorkoutData? = summary.map {
            WhoopWorkoutData(
                strain: $0.strain,
                averageHeartRate: $0.averageHeartRate,
                maxHeartRate: 0,
                caloriesBurned: $0.caloriesBurned,
                durationMinutes: $0.durationMinutes,
                sportID: $0.sportID,
                startTime: $0.startTime
            )
        }
        persistNonGymCompletion(whoop: whoopData, modelContext: modelContext)
        nonGymActivityState = .saved(summary)
    }

    /// User rejected the found activity ("not football"). Stop prompting about
    /// the Whoop activity for today; they can still log manually. Not persisted
    /// across launches — re-fetches next session, which is fine (rare case).
    func dismissNonGymActivity() {
        nonGymActivityState = .dismissed
    }

    private static func summary(from w: WhoopWorkoutData) -> WhoopActivitySummary {
        WhoopActivitySummary(
            strain: w.strain,
            averageHeartRate: w.averageHeartRate,
            durationMinutes: w.durationMinutes,
            caloriesBurned: w.caloriesBurned,
            sportID: w.sportID,
            startTime: w.startTime
        )
    }

    private static func summary(from s: ActivitySession) -> WhoopActivitySummary? {
        guard let strain = s.strain else { return nil } // manual entry: no metrics
        return WhoopActivitySummary(
            strain: strain,
            averageHeartRate: s.averageHeartRate ?? 0,
            durationMinutes: s.durationMinutes ?? 0,
            caloriesBurned: s.caloriesBurned ?? 0,
            sportID: s.sportID,
            startTime: s.startTime
        )
    }

    /// Whoop sport id for a Tempo workout type. Only football maps to a known
    /// Whoop sport (soccer == 1) today; the rest fall back to -1 (no tagged
    /// match expected, so they take the untagged/none branches).
    private static func whoopSportID(for type: WorkoutType) -> Int {
        switch type {
        case .football: 1 // Whoop "Soccer"
        default: -1
        }
    }

    // MARK: - Reorder Exercises

    func moveExercises(from source: IndexSet, to destination: Int) {
        guard let plan = todayPlan else {
            return
        }
        var exercises = plan.orderedExercises
        exercises.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in exercises.enumerated() {
            exercise.order = index
        }
    }

    // MARK: - Add / Remove Sets

    func addSet(to exerciseIndex: Int, modelContext: ModelContext) {
        guard let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises
        guard exerciseIndex < exercises.count else {
            return
        }

        let plannedExercise = exercises[exerciseIndex]
        let sets = plannedExercise.orderedSets
        let lastSet = sets.last
        let newSetNumber = (lastSet?.setNumber ?? 0) + 1
        let targetReps = lastSet?.targetReps ?? 8
        let targetWeight = lastSet?.targetWeight

        let newSet = PlannedSet(
            setNumber: newSetNumber,
            targetReps: targetReps,
            targetWeight: targetWeight,
            plannedExercise: plannedExercise
        )

        if plannedExercise.sets != nil {
            plannedExercise.sets?.append(newSet)
        } else {
            plannedExercise.sets = [newSet]
        }

        try? modelContext.save()
        HapticManager.selection()
    }

    func removeLastUncompletedSet(from exerciseIndex: Int, modelContext: ModelContext) {
        guard let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises
        guard exerciseIndex < exercises.count else {
            return
        }

        let plannedExercise = exercises[exerciseIndex]
        let sets = plannedExercise.orderedSets

        // Must keep at least 1 set
        guard sets.count > 1 else {
            return
        }

        // Remove the last uncompleted set
        if let lastUncompleted = sets.last(where: { !$0.completed }) {
            plannedExercise.sets?.removeAll { $0.id == lastUncompleted.id }
            modelContext.delete(lastUncompleted)
            try? modelContext.save()
            HapticManager.selection()
        }
    }

    // MARK: - Pause / Resume

    // Per STATE_MACHINES.md — any active → paused

    func pause() {
        guard sessionState.isActive else {
            return
        }

        let previousState: WorkoutSessionState.PausedFromState
        switch sessionState {
        case let .warmup(ei, si):
            previousState = .warmup(exerciseIndex: ei, warmupSetIndex: si)
        case let .exercise(sub):
            previousState = .exercise(sub)
        case .cooldown:
            previousState = .cooldown
        default:
            return
        }

        stopRestTimer()
        stopWarmupMoveTimer()
        stopElapsedTimer()
        sessionState = .paused(previousState: previousState, pauseStartTime: Date())
    }

    func resume() {
        guard case let .paused(previousState, pauseStart) = sessionState else {
            return
        }

        // Track pause duration
        totalPauseDuration += Date().timeIntervalSince(pauseStart)

        // Restore previous state
        switch previousState {
        case let .warmup(ei, si):
            sessionState = .warmup(exerciseIndex: ei, warmupSetIndex: si)
            // Re-arm the guided warm-up move timer; the elapsed clock does not
            // run during warm-up, so don't start it here.
            startWarmupMoveTimerForCurrent()
            return
        case let .exercise(sub):
            sessionState = .exercise(sub)
        case .cooldown:
            sessionState = .cooldown
        }

        startElapsedTimer()
    }

    // MARK: - Computed Properties

    // Display-value computed properties moved to TrainingViewModel+Computed.swift
    // (split out to keep this file under the SwiftLint length caps).

    // MARK: - Timers / Audio / Notifications

    // Rest/warm-up/elapsed timers, audio cues, rest notifications, and the
    // resetState/restDuration helpers moved to TrainingViewModel+Timers.swift.

    // MARK: - Exercise Population

    // populateExercises + selection/superset/priority/defaultWeight helpers
    // live in TrainingViewModel+ExercisePopulation.swift (split out to keep
    // this file under the SwiftLint length caps).

    // MARK: - Injury / Pain Note Scan (Tier 2.3)

    /// Pain/injury keywords scanned in user notes. Lowercased, substring match.
    private static let painKeywords = [
        "hurt", "pain", "painful", "tweak", "strain", "pinch", "pinched",
        "sore", "injury", "injured", "tendon", "ache", "aching", "sharp",
    ]

    /// Recently (last `days`) flagged exercise IDs — any USER-PROVIDED note
    /// mentioning pain, mapped back to its exercise via the still-intact
    /// plannedSet relationship. Transient (scanned fresh each call, no stored
    /// flag) so it always reflects the latest notes and adds no migration.
    /// Pruned/legacy feedback whose relationship is nil is simply skipped.
    func painFlaggedExerciseIDs(within days: Int = 21, modelContext: ModelContext) -> Set<UUID> {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let descriptor = FetchDescriptor<SetFeedback>(
            predicate: #Predicate<SetFeedback> { $0.userProvidedFeedback && $0.capturedAt >= cutoff }
        )
        guard let rows = try? modelContext.fetch(descriptor) else {
            return []
        }
        var flagged: Set<UUID> = []
        for row in rows {
            guard let note = row.note?.lowercased(), !note.isEmpty else {
                continue
            }
            guard Self.painKeywords.contains(where: { note.contains($0) }) else {
                continue
            }
            if let exID = row.plannedSet?.plannedExercise?.exercise?.id {
                flagged.insert(exID)
            }
        }
        return flagged
    }

    // MARK: - Feedback Aggregation (Tier 2.1, pure + unit-tested)

    /// Aggregate a session's USER-PROVIDED feedback for one exercise's completed
    /// working sets into the values stored on ExerciseHistory. Pure (no context,
    /// no VM state) so it's unit-testable without a device. `enteredFeedback` is
    /// keyed by `PlannedSet.id` and must already be filtered to
    /// userProvidedFeedback==true rows. Zero matches → (nil, nil, 0) = "no signal".
    nonisolated static func aggregateFeedback(
        completedSets: [PlannedSet],
        enteredFeedback: [UUID: SetFeedback]
    ) -> (avgRPE: Double?, worstFormRaw: String?, count: Int, gassedFraction: Double?) {
        let fb = completedSets.compactMap { enteredFeedback[$0.id] }
        guard !fb.isEmpty else {
            return (nil, nil, 0, nil)
        }
        let avgRPE = Double(fb.map(\.rpe).reduce(0, +)) / Double(fb.count)
        let worstForm = fb.map(\.formQuality).max { $0.severityRank < $1.severityRank }
        // Conditioning-debt signal: fraction of entered rows the user tagged
        // `.gassed`. Read by TrainingEngine.restMultiplier.
        let gassedCount = fb.filter { $0.breathDifficulty.isNegativeSignal }.count
        let gassedFraction = Double(gassedCount) / Double(fb.count)
        return (avgRPE, worstForm?.rawValue, fb.count, gassedFraction)
    }

    // assignSupersetGroups / muscleGroups / selectExercises /
    // exercisePriorityOrder / defaultWeight moved to
    // TrainingViewModel+ExercisePopulation.swift.

    // MARK: - User Settings Loaders

    private func loadFootballDays(modelContext: ModelContext) -> ActiveDays {
        let descriptor = FetchDescriptor<UserSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            return settings.footballDays
        }
        return ActiveDays(rawValue: 0) // no football days
    }

    private func loadTrainingSplit(modelContext: ModelContext) -> TrainingSplit {
        let descriptor = FetchDescriptor<UserSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            return settings.trainingSplit
        }
        return .pushPullLegs // default
    }

    private func loadDeloadSettings(modelContext: ModelContext) -> (frequency: Int, startDate: Date?) {
        let descriptor = FetchDescriptor<UserSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            let startDate = settings.userProfile?.createdAt
            return (frequency: settings.deloadFrequencyWeeks, startDate: startDate)
        }
        return (frequency: 5, startDate: nil)
    }

    private func loadRecoveryScore(modelContext: ModelContext) -> Double? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date == today },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first?.recoveryScore
    }

    /// Per-day recovery scores for the 7-day window starting at `startDate`.
    /// Missing days are omitted (engine falls back to green/unknown for those).
    private func loadRecoveryScores(modelContext: ModelContext, startDate: Date) -> [Date: Double] {
        let cal = Calendar.current
        let weekStart = cal.startOfDay(for: startDate)
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) else {
            return [:]
        }
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= weekStart && $0.date < weekEnd }
        )
        guard let rows = try? modelContext.fetch(descriptor) else { return [:] }
        var result: [Date: Double] = [:]
        for row in rows {
            let key = cal.startOfDay(for: row.date)
            result[key] = row.recoveryScore
        }
        return result
    }
}
