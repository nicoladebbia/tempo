//
// TrainingViewModel.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import AudioToolbox
import AVFoundation
import CallKit
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
            // §3.9 — every transition mirrors onto the Live Activity (started
            // in startWorkout; update/end no-op when none is running).
            if oldValue != sessionState {
                syncLiveActivity()
            }
        }
    }

    // MARK: - Live Activity (§3.9)

    /// Snapshot of the running session for the lock screen / Dynamic Island.
    /// nil in states that shouldn't show an activity (idle/summary/…).
    private func liveActivityState() -> WorkoutActivityAttributes.ContentState? {
        guard let plan = todayPlan else {
            return nil
        }
        let exercises = plan.orderedExercises
        let currentName = exercises.indices.contains(currentExerciseIndex)
            ? (exercises[currentExerciseIndex].exercise?.name ?? "Exercise")
            : "Exercise"

        func state(
            exerciseName: String,
            setText: String,
            isResting: Bool = false,
            restEndsAt: Date? = nil,
            isPaused: Bool = false
        ) -> WorkoutActivityAttributes.ContentState {
            WorkoutActivityAttributes.ContentState(
                workoutType: plan.type.displayName.uppercased(),
                exerciseName: exerciseName,
                setText: setText,
                completedSets: completedSets,
                totalSets: totalSets,
                isResting: isResting,
                restEndsAt: restEndsAt,
                startedAt: workoutStartTime,
                isPaused: isPaused
            )
        }

        switch sessionState {
        case .warmup:
            return state(exerciseName: "Warm-Up", setText: "Guided warm-up")
        case .exercise(.setActive):
            return state(exerciseName: currentName, setText: setCountText)
        case .exercise(.resting):
            return state(
                exerciseName: restContext.exercise?.name ?? currentName,
                setText: setCountText,
                isResting: true,
                restEndsAt: restEndDate
            )
        case .exercise(.betweenExercises):
            return state(exerciseName: currentName, setText: "Next exercise")
        case .paused, .interruptedCall:
            return state(exerciseName: currentName, setText: setCountText, isPaused: true)
        case .cooldown:
            return state(exerciseName: "Cooldown", setText: "Almost done")
        case .idle, .summary, .saved, .discarded, .crashedRecovery:
            return nil
        }
    }

    private func syncLiveActivity() {
        if let state = liveActivityState() {
            Task {
                await WorkoutActivityManager.shared.update(state: state)
            }
        } else {
            WorkoutActivityManager.shared.endCurrentDetached()
        }
    }

    /// Request the activity at session start (updates keep it fresh after).
    func startLiveActivity() {
        guard let plan = todayPlan, let state = liveActivityState() else {
            return
        }
        WorkoutActivityManager.shared.start(planID: plan.id.uuidString, state: state)
    }

    var todayPlan: WorkoutPlan?
    var weekPlans: [WorkoutPlan] = []
    var isLoading = true
    var isDeloadWeek = false
    /// §19.3 — the active deload style (drives banner copy + how the
    /// prescription lightens). Loaded with the deload check.
    var deloadStyle: DeloadStyle = .intensityCut

    /// Set when a data-guarding save fails after retry (workout completion,
    /// activity log, daily-coach session). The tab views bind an alert to this
    /// so a failure that would lose logged training is LOUD, never silent —
    /// the old `try? save()` here was indistinguishable from success while the
    /// user's history evaporated. nil = no pending failure.
    var saveErrorMessage: String?

    /// Re-entrancy guard for `loadToday`. The load is a heavy async pipeline
    /// (week-gen → AI hydration → readiness session) fired from several view
    /// lifecycle points (`.task` on the Training tab, the Move quadrant detail,
    /// a manual "Generate" button) and none of it checks `Task.isCancelled`.
    /// Without coalescing, tab-switching/taps over a long session stack
    /// overlapping pipelines that each hold fetches + regenerate plans —
    /// unbounded memory growth (a jetsam suspect). This is a private
    /// in-flight flag (NOT `isLoading`, which defaults true and would block
    /// the first load); a concurrent call is dropped, the next `.task` reloads.
    private var isReloadInFlight = false

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

    /// Rest-timer prefs, loaded from UserSettings in loadToday. `autoStartRest`
    /// gates whether the rest timer starts automatically after a logged set
    /// (false → advance straight to the next set). `defaultRestSeconds` is the
    /// global fallback used by restDuration(for:) when an exercise has no
    /// per-exercise override.
    var autoStartRest: Bool = true
    var defaultRestSeconds: Int = 120

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
    /// §5 calendar awareness — exams + day load into the daily prompt.
    /// Optional: paths that only ensure the plan (DailyResetCoordinator)
    /// don't need it; the picture just omits the calendar lines.
    private let calendarService: (any CalendarServiceProtocol)?

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
        apiClient: APIClient? = nil,
        calendarService: (any CalendarServiceProtocol)? = nil
    ) {
        self.trainingEngine = trainingEngine
        self.whoop = whoop
        self.healthKit = healthKit
        self.apiClient = apiClient
        self.calendarService = calendarService
    }

    // MARK: - Load Today's Workout

    func loadToday(modelContext: ModelContext) async {
        // Coalesce re-entrant loads: if a pipeline is already running, drop this
        // call rather than stacking a second heavy run. `@MainActor` means the
        // flag flip is race-free; `defer` clears it on every exit path.
        guard !isReloadInFlight else { return }
        isReloadInFlight = true
        defer { isReloadInFlight = false }

        isLoading = true

        // Display unit for the session (weights are stored kg).
        if let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first {
            weightUnit = settings.weightUnit
            autoStartRest = settings.autoStartRestTimer
            defaultRestSeconds = settings.defaultRestSeconds
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

        // Re-snap prescriptions onto the loadable lattice in the user's
        // display unit — covers plans generated before snapping existed and
        // plans generated under the other unit after a kg↔lbs switch.
        // Idempotent; logged sets are never touched.
        snapPrescribedWeights(for: resolved.plan, modelContext: modelContext)
        for plan in weekPlans where plan.id != resolved.plan.id {
            snapPrescribedWeights(for: plan, modelContext: modelContext)
        }

        // Tier 2.3 — refresh the pain-flag cache for the session UI (covers
        // plans that were already populated in a prior load, where
        // populateExercises didn't run this time).
        painFlaggedExercises = painFlaggedExerciseIDs(modelContext: modelContext)

        // Check deload week status (Phase 3: fatigue trend can trigger early).
        // §19.3 — the Auto Deload toggle is now honored (it was saved but
        // never read, so turning it off didn't actually stop deload weeks).
        let deloadSettings = loadDeloadSettings(modelContext: modelContext)
        deloadStyle = deloadSettings.style
        isDeloadWeek = deloadSettings.enabled && trainingEngine.isDeloadWeek(
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

        // D4 §17 — offer the monthly review inside the month-boundary window.
        monthlyReviewDueKey = monthlyReviewDue(modelContext: modelContext)
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

    /// §14 requirement (d) — the learned spare-day easy-modality cycle order,
    /// derived from what the user actually logged (manual completions AND Whoop
    /// imports both write canonical `WorkoutType` rawValues) over the trailing 4
    /// weeks. Runs vs swims decide which modality leads; the pure ranking lives in
    /// `TrainingEngine.easyModalityOrder`. Thin/balanced history → pool-first.
    private func learnedEasyModalityOrder(modelContext: ModelContext) -> [WorkoutType] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -28, to: Date()) else { return [.pool, .run] }
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.date >= cutoff }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let pools = rows.filter { $0.workoutType == WorkoutType.pool.rawValue }.count
        let runs = rows.filter { $0.workoutType == WorkoutType.run.rawValue }.count
        return TrainingEngine.easyModalityOrder(poolLogged: pools, runLogged: runs)
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
        //    Calendar context (exams ≤7d, today's event load) is fetched here —
        //    the only async input — and handed to the sync assembler.
        let calendarContext = await fetchCalendarContext()
        let picture = assembleTodayPicture(modelContext: modelContext, calendarContext: calendarContext)

        // 2. brainEligible = DATA readiness only (≥30d history AND Whoop fresh).
        //    Entitlement (Pro/consent) is NOT checked here — the coach's 402→
        //    fallback owns that; duplicating risks the two disagreeing.
        let brainEligible = picture.hasBaselineForBrain && isWhoopFresh(modelContext: modelContext)

        // 3. Deterministic candidate (cold-start / offline / 402 / parse-fail
        //    fallback) built from the planned modality. Floor still applies to it.
        //    (b)+(c) compose: a two-a-day places its two parts in real calendar
        //    windows (lift in the preferred/free slot, cardio spaced) rather than
        //    a fixed clock; nil → the 08:00/18:00 fallback inside the candidate.
        let secondaryWindows = plan.isTwoADay ? await twoADayWindows(modelContext: modelContext) : nil
        let candidate = deterministicCandidate(for: plan, readiness: picture, secondaryWindows: secondaryWindows)

        // 4. Coach: produce-then-floor.
        let coach = DailyReadinessCoach(apiClient: apiClient)
        let result = await coach.session(
            for: picture,
            plannedModality: plan.type.rawValue,
            deterministicCandidate: candidate,
            brainEligible: brainEligible
        )

        // 5. Persist the DailySession 1:1 (every day — uniform link, §8 revised).
        //    Dedup BEFORE insert — always on, not just the DEBUG force path: a
        //    failed save below leaves today's pending row in the context with
        //    the day-key unconsumed, so the next loadToday re-enters here and
        //    must not stack a second row for the same day.
        if let stale = fetchTodayDailySession(modelContext: modelContext) {
            modelContext.delete(stale)
        }
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
        } else if plan.status == .planned,
                  let mapped = WorkoutType.fromModality(result.decision.session.modality),
                  mapped != plan.type {
            // §8 connect — the brain kept the planned modality unless readiness
            // forced a move; when it DID move (planned pool → prescribed rest at
            // yellow), the plan ROW must follow, or the header/week views keep
            // showing the old day next to a card that says otherwise. The
            // template type is stashed once for the "keep planned workout"
            // override and the planResolution keep-rule.
            if plan.plannedTypeRaw == nil { plan.plannedTypeRaw = plan.typeRaw }
            plan.type = mapped
            #if DEBUG
                print("\(DebugTrace.prefix)[daily_coach] plan reshaped \(plan.plannedTypeRaw ?? "?") → \(mapped.rawValue) (tier=\(result.decision.tier.rawValue))")
            #endif
        }

        // Consume the day-key and save ATOMICALLY: key set before the save so
        // success persists both together; on failure the key is REVERTED so
        // the guard at the top doesn't strand the user on a fallback for 24h —
        // the next loadToday re-runs the coach (the dedup above absorbs the
        // pending row, and a duplicate cheap coach call beats a lost day).
        let priorDayKey = profile.lastDailySessionDayKey
        profile.lastDailySessionDayKey = todayKey
        if !saveGuarded(modelContext, operation: "coach session") {
            profile.lastDailySessionDayKey = priorDayKey
        }
        dailySession = session

        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] session persisted source=\(result.source.rawValue) tier=\(result.decision.tier.rawValue) modality=\(session.modality) planSkipped=\(result.decision.tier == .severe)")
        #endif
    }

    /// Assemble today's ReadinessPicture from the trailing-30-day DailyRecovery
    /// history (reuses the canonical forward-sorted fetch).
    private func assembleTodayPicture(
        modelContext: ModelContext,
        calendarContext: (exams: [ExamSnapshot], busyHours: Double?) = ([], nil)
    ) -> ReadinessPicture {
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
                sleepDebt: r.sleepDebt, strain: r.strain, deepSleepMin: r.deepSleepMin,
                skinTemp: r.skinTemp, spo2: r.spo2, sleepConsistency: r.sleepConsistency
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
            yesterdaySessions: fetchYesterdaySessions(modelContext: modelContext),
            yesterdaySessionRPE: fetchYesterdaySessionRPE(modelContext: modelContext),
            bodyComp: bodyComp,
            checkIn: checkIn,
            daysUntilNextMatch: daysUntilNextMatch,
            blockEmphasis: currentBlockEmphasis(modelContext: modelContext),
            venueToday: venueTodaySnapshot(modelContext: modelContext),
            examsSoon: calendarContext.exams,
            busyHoursToday: calendarContext.busyHours
        )
    }

    /// §5 calendar awareness — exams in the next 7 days + today's scheduled
    /// hours. EventKit failures (no auth, no service) read as "no calendar
    /// signal", never an error: the picture just omits the lines.
    private func fetchCalendarContext() async -> (exams: [ExamSnapshot], busyHours: Double?) {
        guard let calendarService else { return ([], nil) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: today),
              let dayEnd = cal.date(byAdding: .day, value: 1, to: today) else { return ([], nil) }

        let exams = calendarService.detectExamDates(in: DateInterval(start: today, end: weekEnd)).map {
            ExamSnapshot(
                subject: $0.subject,
                daysUntil: cal.dateComponents([.day], from: today, to: cal.startOfDay(for: $0.date)).day ?? 0
            )
        }

        let events = (try? await calendarService.fetchEvents(for: DateInterval(start: today, end: dayEnd))) ?? []
        let busyMinutes = events
            .filter { !$0.isAllDay }
            .reduce(0.0) { $0 + max(0, $1.endDate.timeIntervalSince($1.startDate) / 60) }
        return (exams, busyMinutes > 0 ? busyMinutes / 60 : nil)
    }

    /// Yesterday's real activities (Whoop-detected, imported, or attested) —
    /// the §13.2 enrichment: what the body actually DID feeds today's picture.
    private func fetchYesterdaySessions(modelContext: ModelContext) -> [ActivitySnapshot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return [] }
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < today }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map {
            ActivitySnapshot(
                workoutType: $0.workoutType, strain: $0.strain,
                durationMinutes: $0.durationMinutes, averageHeartRate: $0.averageHeartRate,
                hardMinutes: $0.hardMinutes
            )
        }
    }

    /// §14 #3 — yesterday's one-tap session RPE (the ACTUAL the user reported
    /// on yesterday's completed plan), surfaced into today's picture so the
    /// brain calibrates against felt cost, not just Whoop strain.
    private func fetchYesterdaySessionRPE(modelContext: ModelContext) -> Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return nil }
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < today && $0.sessionRPE != nil }
        )
        return (try? modelContext.fetch(descriptor))?.first?.sessionRPE
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
    /// §21 (b) + (c) compose — place a two-a-day's two sessions in REAL calendar
    /// windows: the LIFT in the user's preferred/available training window (the
    /// same `suggestWorkoutWindow` that drives the "best window" banner), the
    /// CARDIO spaced ≥6h away on the opposite side of the day. Returns nil — so
    /// the deterministic 08:00/18:00 fallback stands — when there's no calendar,
    /// no free window, or no placement that keeps a valid ≥6h gap in waking hours.
    private func twoADayWindows(modelContext: ModelContext) async -> (liftMin: Int, cardioMin: Int)? {
        guard let calendarService else { return nil }
        let pref = (try? modelContext.fetch(FetchDescriptor<UserDailyPlanProfile>()))?
            .first?.trainingTimePreference ?? .anyFree
        guard let window = await calendarService.suggestWorkoutWindow(for: Date(), preferring: pref) else { return nil }
        let cal = Calendar.current
        let liftMin = cal.component(.hour, from: window.start) * 60 + cal.component(.minute, from: window.start)
        // Space the cardio flush ≥8h from the lift, on the opposite side of the
        // day, clamped to a waking-hours start (06:00–21:00).
        let cardioMin = liftMin < 13 * 60
            ? min(liftMin + 8 * 60, 21 * 60) // morning lift → evening flush
            : max(liftMin - 8 * 60, 6 * 60)  // later lift → morning flush
        guard abs(cardioMin - liftMin) >= 6 * 60 else { return nil } // gap collapsed → fallback
        return (min(liftMin, cardioMin), max(liftMin, cardioMin))    // earliest part first
    }

    func deterministicCandidate(for plan: WorkoutPlan, readiness: ReadinessPicture? = nil,
                                secondaryWindows: (liftMin: Int, cardioMin: Int)? = nil) -> DailySessionDTO {
        let type = plan.type
        let dur = plan.durationMinutes ?? 45
        // Rich-signal ease gate (recovery number + acute:chronic strain + HRV
        // trend, not a bucket). Fires only for the cold-start / offline / 402
        // deterministic path; the brain refines this when eligible, and the
        // safety floor still tiers whatever comes out. nil (no data) = never ease.
        let ease = readiness?.easeCrossTrainingToday ?? false
        let mk: (BlockKind, String?, String) -> SessionBlockDTO = { kind, split, label in
            SessionBlockDTO(kind: kind, label: label, notes: nil, cue: nil, scheduledMin: nil, split: split,
                            reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                            durationSec: nil, stroke: nil, runType: nil, paceSecPerKm: nil, sets: nil)
        }
        // An easy recovery swim — the flush a compromised hard cross-training day
        // is stepped down to (conditioning/sprint → pool), and the shape pool days
        // already take. Duration trimmed on an eased day.
        let easySwim: (Int, String) -> DailySessionDTO = { minutes, why in
            DailySessionDTO(
                modality: "pool", intensity: .easy, durationMin: minutes,
                blocks: [SessionBlockDTO(kind: .pool, label: "Easy swim", notes: nil,
                                         cue: "Long strokes, easy pace.", scheduledMin: nil, split: nil,
                                         reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                                         durationSec: minutes * 60, stroke: "freestyle", runType: nil,
                                         paceSecPerKm: nil, sets: nil)],
                shortWhy: why, fullWhy: nil, expectedStrain: nil, expectedSessionRPE: 3
            )
        }
        switch type {
        case .push, .pull, .legs, .upper, .lower, .fullBody:
            // §21 two-a-day (requirement (b)) — the week generator marked this GYM
            // day to also carry an easy cardio SECOND session. Emit BOTH as TIMED
            // parts (lift 08:00, cardio 18:00 → a 10h gap that clears the floor's
            // ≥6h composite rule; two untimed blocks would merge into one part, so
            // both must carry a scheduledMin). The Today card then renders two
            // time-separated sections via `.parts`. DROP the second session on a
            // low-readiness morning — the same §2 ease gate that trims cross-
            // training; the safety floor's ACWR/gap rules are the backstop.
            if let second = plan.secondarySessionType, !ease {
                // Timing (requirement (c) composes here): the caller places the
                // lift in the user's REAL calendar/preferred window and spaces the
                // cardio; absent calendar data we fall back to a fixed 08:00/18:00
                // split (still a valid ≥6h gap for the floor).
                let (liftMin, cardioMin) = secondaryWindows ?? (8 * 60, 18 * 60)
                let lift = SessionBlockDTO(
                    kind: .gym, label: type.displayName, notes: nil, cue: nil,
                    scheduledMin: liftMin, split: type.rawValue, reps: nil, distanceM: nil,
                    restSec: nil, intensityPct: nil, durationSec: nil, stroke: nil,
                    runType: nil, paceSecPerKm: nil, sets: nil)
                let isRun = second == .run
                let cardio = SessionBlockDTO(
                    kind: isRun ? .run : .pool,
                    label: isRun ? "Easy run" : "Easy swim", notes: nil,
                    cue: "Easy pace — this is the flush, not extra work.",
                    scheduledMin: cardioMin, split: nil, reps: nil, distanceM: nil,
                    restSec: nil, intensityPct: nil, durationSec: 30 * 60,
                    stroke: isRun ? nil : "freestyle", runType: nil,
                    paceSecPerKm: nil, sets: nil)
                return DailySessionDTO(
                    modality: type.rawValue, intensity: .moderate, durationMin: dur,
                    blocks: [lift, cardio],
                    shortWhy: "Lift, then an easy \(second.displayName.lowercased()) — you've got the headroom today.",
                    fullWhy: nil, expectedStrain: nil, expectedSessionRPE: nil)
            }
            return DailySessionDTO(
                modality: type.rawValue, intensity: .moderate, durationMin: dur,
                blocks: [mk(.gym, type.rawValue, type.displayName)],
                shortWhy: "Today's planned \(type.displayName.lowercased()).", fullWhy: nil,
                expectedStrain: nil, expectedSessionRPE: nil
            )
        case .run:
            // Already easy aerobic; on a compromised day, trim the duration.
            let runDur = ease ? max(20, Int(Double(dur) * 0.7)) : dur
            return DailySessionDTO(
                modality: "run", intensity: .easy, durationMin: runDur,
                blocks: [SessionBlockDTO(kind: .run, label: "Easy run", notes: nil, cue: nil, scheduledMin: nil, split: nil,
                                         reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                                         durationSec: runDur * 60, stroke: nil, runType: "tempo",
                                         paceSecPerKm: nil, sets: nil)],
                shortWhy: ease ? "Recovery is down — keep the run short and easy." : "Easy aerobic run.",
                fullWhy: nil, expectedStrain: nil, expectedSessionRPE: 4
            )
        case .sprint, .conditioning:
            // Discretionary HARD cross-training. On a compromised day, swap the
            // modality itself for an easy flush — the floor only clamps intensity,
            // it never does this. Football is a real fixture, handled below.
            if ease {
                return easySwim(max(20, Int(Double(dur) * 0.7)),
                                "Recovery is down — swapped the hard conditioning for an easy flush swim.")
            }
            return DailySessionDTO(
                modality: type.rawValue, intensity: .moderate, durationMin: dur,
                blocks: [mk(.field, nil, type.displayName)],
                shortWhy: "Today's \(type.displayName.lowercased()).", fullWhy: nil,
                expectedStrain: nil, expectedSessionRPE: 5
            )
        case .football:
            // A real fixture — the user shows up regardless; never swapped out.
            return DailySessionDTO(
                modality: type.rawValue, intensity: .moderate, durationMin: dur,
                blocks: [mk(.field, nil, type.displayName)],
                shortWhy: "Today's \(type.displayName.lowercased()).", fullWhy: nil,
                expectedStrain: nil, expectedSessionRPE: 5
            )
        case .pool:
            // Already easy; trim the duration on a compromised day.
            let poolDur = ease ? max(20, Int(Double(dur) * 0.7)) : dur
            return easySwim(poolDur,
                            ease ? "Recovery is down — keep the swim short and easy."
                                 : "Easy recovery swim — flush the legs.")
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
        existingPlannedTypeRaw: String? = nil,
        templateType: WorkoutType
    ) -> PlanResolution {
        switch existingStatus {
        case .planned:
            if existingType == templateType { return .keep }
            // §8 connect — the row WAS the template type before the daily
            // brain moved it (planned pool → rest at yellow). The mismatch is
            // deliberate; replacing would resurrect the desync every app-open.
            // If the TEMPLATE itself changed (user edited the schedule), the
            // stash no longer matches and the template rightly wins.
            if existingPlannedTypeRaw == templateType.rawValue { return .keep }
            return .replace
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
                   existingPlannedTypeRaw: existing.plannedTypeRaw,
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
               existing.secondarySessionTypeRaw != canonical.secondarySessionTypeRaw {
                existing.secondarySessionTypeRaw = canonical.secondarySessionTypeRaw
                if canonical.secondarySessionTypeRaw == nil { existing.secondaryCompleted = false }
                try? modelContext.save()
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
           ) {
            plan.type = .mobility
            plan.notes = "Deload — full rest week. Move, stretch, recover."
        }
        populateExercises(for: plan, modelContext: modelContext)
        modelContext.insert(plan)
        try? modelContext.save()
        return ResolvedTodayPlan(plan: plan, isCrashedInProgress: false)
    }

    // MARK: - Load Week Plan

    /// Shared week assembly: reads every generation input (split, custom map,
    /// recovery, matches, emphasis, learned modality) and generates the week
    /// starting at `monday`. Ephemeral — nothing is persisted here; callers
    /// decide whether to populate exercises / assign to `weekPlans`.
    private func assembleWeekPlans(
        startingMonday monday: Date,
        modelContext: ModelContext,
        referenceDate: Date
    ) -> [WorkoutPlan] {
        let cal = Calendar.current
        let footballDays = loadFootballDays(modelContext: modelContext)
        let split = loadTrainingSplit(modelContext: modelContext)
        // Advanced custom split — user's per-weekday map (nil unless configured).
        let customWeekdayMap = loadCustomWeekdayPlan(modelContext: modelContext)
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

        let plans = trainingEngine.generateWeekPlan(
            startDate: monday,
            recoveryScores: recoveryScores,
            footballDays: footballDays,
            split: split,
            customWeekdayMap: customWeekdayMap,
            recoveryThresholdOffset: signals.thresholdOffset,
            matchDayKeys: matchDayKeys,
            competitiveMatchDayKeys: competitiveMatchDayKeys,
            // §14 Decision 1 — soccer emphasis re-shapes spare days (visible
            // in This Week); physique keeps the pre-emphasis week exactly.
            emphasis: currentBlockEmphasis(modelContext: modelContext) ?? .physique,
            // §14 requirement (d) — bias the spare-day easy modality toward what
            // he actually logs (runs vs swims) over the trailing 4 weeks.
            easyModalityPreference: learnedEasyModalityOrder(modelContext: modelContext),
            // §21 (b) — the two-a-day slot skips days already past this week.
            referenceDate: referenceDate
        )

        // §19.3 full-rest deload: every gym day of a deload week becomes
        // mobility. Football/rest/cardio days keep their shape — you still
        // play; you just don't lift.
        let deload = loadDeloadSettings(modelContext: modelContext)
        if deload.enabled, deload.style == .fullRest,
           trainingEngine.isDeloadWeek(
               date: monday,
               deloadFrequencyWeeks: deload.frequency,
               trainingStartDate: deload.startDate,
               fatigueEWMA: signals.fatigueEWMA
           ) {
            for plan in plans where plan.type.isGymWorkout {
                plan.type = .mobility
                plan.notes = "Deload — full rest week. Move, stretch, recover."
            }
        }
        return plans
    }

    /// Ephemeral preview of a future week (§9.4 week navigation) — generated
    /// from the same inputs as the live week but NEVER persisted and never
    /// exercise-populated. Future recovery scores don't exist → green defaults.
    func previewWeekPlans(startingMonday monday: Date, modelContext: ModelContext) -> [WorkoutPlan] {
        assembleWeekPlans(
            startingMonday: monday,
            modelContext: modelContext,
            // All days are "future" relative to that week's own Monday.
            referenceDate: monday
        )
    }

    func loadWeekPlan(modelContext: ModelContext) {
        let cal = Calendar.current
        let today = Date()

        // Find Monday of this week
        var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps.weekday = 2 // Monday
        let monday = cal.date(from: comps) ?? today

        weekPlans = assembleWeekPlans(
            startingMonday: monday,
            modelContext: modelContext,
            referenceDate: today
        )

        // Check deload week status (Phase 3: fatigue trend can trigger early).
        // Gated on the Auto Deload toggle (§19.3 — it was previously ignored).
        let deloadSettings = loadDeloadSettings(modelContext: modelContext)
        deloadStyle = deloadSettings.style
        isDeloadWeek = deloadSettings.enabled && trainingEngine.isDeloadWeek(
            date: Date(),
            deloadFrequencyWeeks: deloadSettings.frequency,
            trainingStartDate: deloadSettings.startDate,
            fatigueEWMA: adaptiveSignals(modelContext: modelContext).fatigueEWMA
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
        // STATE_MACHINES §1 — watch for phone calls only while a session runs.
        startCallMonitoring()

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
        // §3.9 — put the session on the lock screen / Dynamic Island.
        startLiveActivity()
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
        // A recovered session earns its lock-screen presence back too (§3.9),
        // and the call monitor that startWorkout would have armed.
        startCallMonitoring()
        startLiveActivity()
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
        addedLoadKg: Double? = nil,
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
        // `weight` is the EFFECTIVE load in kg (for bodyweight lifts the caller
        // passes bodyweight ± addedLoadKg); addedLoadKg records the signed input.
        set.actualWeight = weight
        set.actualReps = reps
        set.addedLoadKg = addedLoadKg
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

        // §6 superset alternation — A1 → B1 with NO rest, then the pair's
        // shared rest, then back: A2 → B2 … Warmup ramps stay in the normal
        // per-exercise flow; alternation starts at the first working set.
        if !set.isWarmup, let partnerIdx = supersetPartnerIndex(of: currentExerciseIndex) {
            let partner = exercises[partnerIdx]
            let isFirstOfPair = partnerIdx > currentExerciseIndex

            if isFirstOfPair, let partnerSet = firstUncompletedSetIndex(in: partner) {
                // First lift logged → straight into the partner, no rest.
                currentExerciseIndex = partnerIdx
                currentSetIndex = partnerSet
                sessionState = .exercise(.setActive(
                    exerciseIndex: partnerIdx, setIndex: partnerSet
                ))
                HapticManager.selection()
                return
            }
            if !isFirstOfPair, let backSet = firstUncompletedSetIndex(in: partner) {
                // Second lift logged → the pair's one rest, then back to the first.
                restOrJump(to: partnerIdx, setIndex: backSet, after: plannedExercise)
                return
            }
            if firstUncompletedSetIndex(in: plannedExercise) == nil {
                // Both lifts fully logged → advance PAST the pair (the standard
                // next-exercise path would land on the already-finished partner).
                let afterPair = max(currentExerciseIndex, partnerIdx) + 1
                if afterPair >= exercises.count {
                    stopElapsedTimer()
                    sessionState = .summary
                } else {
                    restOrJump(to: afterPair, setIndex: 0, after: plannedExercise)
                }
                return
            }
            // Partner done, this lift still has sets → finish it in the
            // standard flow below.
        }

        if isLastSet, isLastExercise {
            // Workout complete → straight to summary (cooldown screen removed;
            // the last set's feedback is editable at the top of the summary).
            stopElapsedTimer()
            sessionState = .summary
        } else if isLastSet {
            // Per STATE_MACHINES.md — between exercises
            if autoStartRest {
                let restDuration = restDuration(for: plannedExercise)
                startRestTimer(duration: restDuration, nextAction: .nextExercise)
                sessionState = .exercise(.resting(
                    exerciseIndex: currentExerciseIndex,
                    setIndex: currentSetIndex,
                    remainingSeconds: restDuration
                ))
            } else {
                // Auto-start off — skip rest, advance straight to the next
                // exercise via the same path the timer uses on completion.
                pendingRestAction = .nextExercise
                advanceAfterRest()
            }
        } else {
            // Per STATE_MACHINES.md — rest between sets
            if autoStartRest {
                let restDuration = restDuration(for: plannedExercise)
                startRestTimer(duration: restDuration, nextAction: .nextSet)
                sessionState = .exercise(.resting(
                    exerciseIndex: currentExerciseIndex,
                    setIndex: currentSetIndex,
                    remainingSeconds: restDuration
                ))
            } else {
                // Auto-start off — skip rest, advance straight to the next set.
                pendingRestAction = .nextSet
                advanceAfterRest()
            }
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

    enum RestNextAction: Equatable {
        case nextSet
        case nextExercise
        /// §6 superset flow — rest ends on an explicit (exercise, set) target:
        /// back to the pair's first lift, or past a fully-logged pair.
        case supersetJump(exerciseIndex: Int, setIndex: Int)
    }

    var pendingRestAction: RestNextAction = .nextSet

    // MARK: - Superset Flow (§6 / §2.8)

    /// Adjacent partner in the same superset pair, or nil. Pairing mirrors the
    /// render logic: CONSECUTIVE orderedExercises sharing a non-nil group
    /// (a reorder that splits adjacency deliberately breaks the pair).
    func supersetPartnerIndex(of index: Int) -> Int? {
        guard let exercises = todayPlan?.orderedExercises,
              index >= 0, index < exercises.count,
              let group = exercises[index].supersetGroup
        else {
            return nil
        }
        if index + 1 < exercises.count, exercises[index + 1].supersetGroup == group {
            return index + 1
        }
        if index - 1 >= 0, exercises[index - 1].supersetGroup == group {
            return index - 1
        }
        return nil
    }

    /// Partner name for the active screen's superset banner. nil when the
    /// current exercise is not part of a pair.
    var currentSupersetPartnerName: String? {
        guard let idx = supersetPartnerIndex(of: currentExerciseIndex),
              let exercises = todayPlan?.orderedExercises
        else {
            return nil
        }
        return exercises[idx].exercise?.name
    }

    private func firstUncompletedSetIndex(in plannedExercise: PlannedExercise) -> Int? {
        plannedExercise.orderedSets.firstIndex { !$0.completed }
    }

    /// Rest toward an explicit (exercise, set) target — honoring the
    /// auto-start-rest preference exactly like the standard paths.
    private func restOrJump(to exerciseIndex: Int, setIndex: Int, after plannedExercise: PlannedExercise) {
        if autoStartRest {
            let duration = restDuration(for: plannedExercise)
            startRestTimer(
                duration: duration,
                nextAction: .supersetJump(exerciseIndex: exerciseIndex, setIndex: setIndex)
            )
            sessionState = .exercise(.resting(
                exerciseIndex: currentExerciseIndex,
                setIndex: currentSetIndex,
                remainingSeconds: duration
            ))
        } else {
            pendingRestAction = .supersetJump(exerciseIndex: exerciseIndex, setIndex: setIndex)
            advanceAfterRest()
        }
    }

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
        case let .supersetJump(exerciseIndex, setIndex):
            currentExerciseIndex = exerciseIndex
            currentSetIndex = setIndex
            sessionState = .exercise(.setActive(
                exerciseIndex: exerciseIndex,
                setIndex: setIndex
            ))
            HapticManager.notification(.warning)
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

    /// Save that guards user data: one retry, then loud failure. Every path
    /// that persists real training (history rows, activity sessions, the daily
    /// coach's session) must route through this instead of `try? save()` —
    /// a swallowed failure here loses logged sets while the UI reports success.
    /// Returns whether the save landed; on false, `saveErrorMessage` is set
    /// and the CALLER must revert any status flags it optimistically flipped
    /// (so the day stays open and a retry can re-run the full path).
    /// Internal (not private) so the split extension files (+WatchSync etc.)
    /// route their persists through the same guard.
    @discardableResult
    func saveGuarded(_ modelContext: ModelContext, operation: String) -> Bool {
        for attempt in 0 ..< 2 {
            do {
                try modelContext.save()
                return true
            } catch {
                #if DEBUG
                    print("\(DebugTrace.prefix)[Workout] saveGuarded(\(operation)) attempt \(attempt) FAILED: \(error)")
                #endif
            }
        }
        saveErrorMessage = "Couldn't save your \(operation). Nothing is lost yet — hit retry, and free up iPhone storage if this keeps happening."
        return false
    }

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

        // Capture pre-completion state so a failed save can revert it — the
        // status flip below is optimistic, and leaving `.completed` standing
        // over an unsaved context locks the day around vanished history.
        let priorStatus = plan.status
        let priorFinishedAt = plan.finishedAt
        let priorDuration = plan.durationMinutes

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

        // Persist to SwiftData — LOUD on failure. On a failed save the status
        // flip is reverted so the day stays open: the pending history inserts
        // remain in the context, the idempotency guard no longer short-circuits,
        // and the SAVE button can re-run this whole path (stale-row dedup above
        // absorbs the re-insert). Bail BEFORE the learning/notification side
        // effects — none of them may act on a completion that didn't land.
        guard saveGuarded(modelContext, operation: "workout") else {
            plan.status = priorStatus
            plan.finishedAt = priorFinishedAt
            plan.durationMinutes = priorDuration
            return false
        }
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
        // Fresh attempt = fresh slate: a STALE failure flag from an unrelated
        // earlier save (e.g. the coach path) must not block THIS save's
        // success path below from resetting the session.
        saveErrorMessage = nil
        // Completion may already be persisted (auto-saved on entering
        // .summary). This call is idempotent; it writes only if it hasn't yet.
        persistCompletion(modelContext: modelContext)

        // A failed save (saveErrorMessage set) must keep the summary open —
        // resetting here would close the session over data that never landed.
        // The alert bound to saveErrorMessage owns the retry.
        guard saveErrorMessage == nil else { return }

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

        let priorStatus = plan.status
        let priorFinishedAt = plan.finishedAt
        let priorDuration = plan.durationMinutes

        plan.status = .completed
        plan.finishedAt = Date()
        if let mins = whoop?.durationMinutes {
            plan.durationMinutes = Int(mins)
        }

        // LOUD on failure, mirroring persistCompletion: revert the optimistic
        // status flip so the day stays open and a retry re-runs the whole path
        // (the stale-ActivitySession dedup above absorbs the re-insert). Bail
        // before venue learning + notifications — nothing may act on an
        // activity log that didn't land.
        guard saveGuarded(modelContext, operation: "activity") else {
            plan.status = priorStatus
            plan.finishedAt = priorFinishedAt
            plan.durationMinutes = priorDuration
            return false
        }

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

    // MARK: - Session RPE (§14 #3 — one-tap actual vs the brain's prediction)

    /// Record the user's whole-session RPE (1–10) on today's completed plan.
    /// One value per day; the capsule UI only renders while sessionRPE == nil,
    /// so this is effectively write-once. No notification fan-out — sRPE feeds
    /// tomorrow's prompt + the accuracy spine, nothing re-renders live today.
    func recordSessionRPE(_ rpe: Int, modelContext: ModelContext) {
        guard (1 ... 10).contains(rpe) else { return }
        guard let plan = todayPlan, plan.status == .completed else { return }
        plan.sessionRPE = rpe
        // Denormalize onto the linked session so the accuracy spine never has to
        // traverse the one-way `.nullify` link (dangling-crash guard — see
        // DailySession.actualSessionRPE). dailySession is today's 1:1 pair.
        dailySession?.actualSessionRPE = rpe
        try? modelContext.save()
        #if DEBUG
            print("\(DebugTrace.prefix)[Workout] recordSessionRPE: plan=\(plan.id) rpe=\(rpe) expected=\(dailySession?.expectedSessionRPE.map(String.init) ?? "nil")")
        #endif
    }

    // MARK: - Keep Planned Workout (§8 connect — the user's side of the seam)

    /// Decline the brain's modality move and restore the planned day ("coach
    /// said rest, I'm swimming anyway"). Only a brain-CHOSEN move is
    /// declinable — a SEVERE floor skip never stashes plannedTypeRaw, so this
    /// is a no-op there by construction. The session is marked overridden so
    /// the card collapses and nothing re-applies the move today.
    func keepPlannedWorkout(modelContext: ModelContext) {
        guard let plan = todayPlan,
              plan.status == .planned,
              let stashed = plan.plannedTypeRaw else { return }
        plan.typeRaw = stashed
        plan.plannedTypeRaw = nil
        dailySession?.userOverrode = true
        try? modelContext.save()
        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] user kept planned workout → \(stashed)")
        #endif
    }

    /// §21 (b) — check off (or undo) the cardio SECOND session of a gym+cardio
    /// two-a-day. The lift's completion rides `status` (the DAY counts as trained
    /// on the lift), so this flag tracks the bonus cardio INDEPENDENTLY — it never
    /// gates the day. No-op on a single-session day.
    ///
    /// Marking it done LOGS the cardio as a manual `ActivitySession` — the same
    /// record a standalone cross-training day writes (persistNonGymCompletion) —
    /// so the bonus session feeds the real intelligence: the §14 (d) modality
    /// learner (doing the two-a-day cardio reinforces the learned preference),
    /// venue patterns, and the load/replan cascade. Undo removes that row, so the
    /// flag and the logged activity never disagree.
    func toggleSecondarySessionComplete(modelContext: ModelContext) {
        guard let plan = todayPlan, plan.isTwoADay, let second = plan.secondarySessionType else { return }
        plan.secondaryCompleted.toggle()

        let planID = plan.id
        let typeRaw = second.rawValue
        // The cardio's own ActivitySession, keyed (planID, type) so it's found on
        // undo. The gym lift writes ExerciseHistory (not ActivitySession), so this
        // is the ONLY ActivitySession for the plan — no collision with the lift.
        let existing = (try? modelContext.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate<ActivitySession> { $0.workoutPlanID == planID && $0.workoutType == typeRaw }
        ))) ?? []
        for row in existing { modelContext.delete(row) } // dedup / undo both start clean

        if plan.secondaryCompleted {
            let cardio = ActivitySession(
                date: Date(), startTime: Date(), workoutType: typeRaw, sportID: -1,
                source: "manual", workoutPlanID: planID,
                strain: nil, averageHeartRate: nil, maxHeartRate: nil,
                caloriesBurned: nil, durationMinutes: 30
            )
            modelContext.insert(cardio)
        }
        try? modelContext.save()

        if plan.secondaryCompleted {
            // Same cross-surface signals as any non-gym completion — feeds venue
            // learning and lets the Move quadrant / recovery cascade react.
            VenuePatternLearner.recompute(modelContext: modelContext)
            NotificationCenter.default.post(
                name: .tempoDayPlanReplanRequested, object: nil,
                userInfo: ["reason": DayPlanReason.workoutLogged.rawValue]
            )
            NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        }
        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] two-a-day second session → \(plan.secondaryCompleted ? "done (logged \(typeRaw))" : "undone (removed)")")
        #endif
    }

    // MARK: - Monthly Review (D4 §17)

    /// Month key with a review currently due (drives the Training-tab card).
    /// Set by loadToday; nil outside the window or once the summary exists.
    var monthlyReviewDueKey: String?

    /// Due = inside the month-boundary window AND the month's summary not yet
    /// generated. An interview saved without a summary (offline) stays due so
    /// the Sonnet call retries on a later open within the window.
    func monthlyReviewDue(modelContext: ModelContext, now: Date = Date()) -> String? {
        guard let key = MonthlyReviewSchedule.dueMonthKey(on: now) else { return nil }
        if let existing = fetchMonthlyReview(monthKey: key, modelContext: modelContext),
           existing.summaryText != nil {
            return nil
        }
        return key
    }

    func fetchMonthlyReview(monthKey: String, modelContext: ModelContext) -> MonthlyReview? {
        let descriptor = FetchDescriptor<MonthlyReview>(
            predicate: #Predicate { $0.monthKey == monthKey }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    func fetchOrCreateMonthlyReview(monthKey: String, modelContext: ModelContext) -> MonthlyReview {
        if let existing = fetchMonthlyReview(monthKey: monthKey, modelContext: modelContext) {
            return existing
        }
        let review = MonthlyReview(monthKey: monthKey)
        modelContext.insert(review)
        try? modelContext.save()
        return review
    }

    /// Map a month of stored rows into the pure aggregator's snapshots
    /// (same @Model→snapshot seam as assembleTodayPicture).
    func assembleMonthlyData(monthKey: String, modelContext: ModelContext) -> MonthlyReviewData? {
        guard let interval = MonthlyReviewSchedule.monthInterval(forKey: monthKey) else { return nil }
        let start = interval.start
        let end = interval.end
        let cal = Calendar.current
        let daysInMonth = cal.range(of: .day, in: .month, for: start)?.count ?? 30

        let planRows = (try? modelContext.fetch(FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let plans = planRows.map {
            MonthPlanSnapshot(
                date: $0.date, typeDisplayName: $0.type.displayName, statusRaw: $0.statusRaw,
                skipReasonRaw: $0.skipReasonRaw, startedAt: $0.startedAt,
                tonnageKg: $0.totalVolume, sessionRPE: $0.sessionRPE
            )
        }

        let bodyRows = (try? modelContext.fetch(FetchDescriptor<BodyComposition>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let body = bodyRows.map {
            MonthBodySample(
                date: $0.date, weightKg: $0.weightKg,
                bodyFatPercent: $0.bodyFatPercent, leanMassKg: $0.leanMassKg
            )
        }

        let recoveryRows = (try? modelContext.fetch(FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let recovery = recoveryRows.map {
            MonthRecoverySample(
                date: $0.date, hrv: $0.hrvRmssd, rhr: $0.restingHR,
                recoveryScore: $0.recoveryScore
            )
        }

        let prRows = (try? modelContext.fetch(FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        ))) ?? []
        let prs = prRows.map {
            MonthPRSnapshot(
                label: "\($0.exercise?.name ?? "Unknown") \($0.typeRaw) \(Int($0.value))kg",
                date: $0.date
            )
        }

        // Calibration spines, month-scoped.
        let logRows = (try? modelContext.fetch(FetchDescriptor<PredictionLog>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.outcomeResolved }
        ))) ?? []
        let sessionRows = (try? modelContext.fetch(FetchDescriptor<DailySession>(
            predicate: #Predicate { $0.date >= start && $0.date < end && $0.expectedSessionRPE != nil }
        ))) ?? []
        let sessionPairs = sessionRows.compactMap { session -> SessionRPEPair? in
            guard let expected = session.expectedSessionRPE,
                  let actual = session.workoutPlan?.sessionRPE else { return nil }
            return SessionRPEPair(date: session.date, expected: expected, actual: actual)
        }

        return MonthlyReviewAggregator.aggregate(
            monthKey: monthKey,
            daysInMonth: daysInMonth,
            plans: plans,
            bodySamples: body,
            recoverySamples: recovery,
            prs: prs,
            exerciseAccuracy: PredictionAccuracy.summarize(logRows),
            sessionAccuracy: PredictionAccuracy.summarizeSessions(sessionPairs)
        )
    }

    /// Generate + persist the Sonnet summary. The ≤1/month gate is
    /// `summaryText == nil` — nothing is marked spent on failure, so a failed
    /// call retries on the next open inside the window (unlike the weekly
    /// hydration guard, a monthly report is worth the retry).
    @discardableResult
    func generateMonthlySummary(for review: MonthlyReview, modelContext: ModelContext) async -> Bool {
        guard review.summaryText == nil else { return false }
        guard let apiClient else { return false }
        guard let data = assembleMonthlyData(monthKey: review.monthKey, modelContext: modelContext) else { return false }

        let interview = MonthInterviewSnapshot(
            wentWell: review.wentWell,
            struggles: review.struggles,
            niggles: review.niggles,
            subjectiveProgress: review.subjectiveProgress,
            goalsNextMonth: review.goalsNextMonth,
            chosenEmphasis: review.chosenEmphasis?.rawValue
        )
        let coach = MonthlyReviewCoach(apiClient: apiClient)
        guard let text = await coach.summary(data: data, interview: interview) else { return false }

        review.summaryText = text
        review.summaryGeneratedAt = Date()
        try? modelContext.save()
        monthlyReviewDueKey = monthlyReviewDue(modelContext: modelContext)
        #if DEBUG
            print("\(DebugTrace.prefix)[monthly_review] summary persisted month=\(review.monthKey) chars=\(text.count)")
        #endif
        return true
    }

    /// §17.1 → §14 seam: the interview's emphasis choice becomes next month's
    /// TrainingBlock (open-ended — superseded by any later declaration).
    /// Idempotent: a block already starting that day means he declared one.
    func applyMonthlyEmphasisChoice(_ review: MonthlyReview, modelContext: ModelContext) {
        guard let emphasis = review.chosenEmphasis,
              let start = MonthlyReviewSchedule.nextMonthStart(afterKey: review.monthKey) else { return }
        let day = Calendar.current.startOfDay(for: start)
        let existing = (try? modelContext.fetch(FetchDescriptor<TrainingBlock>())) ?? []
        guard !existing.contains(where: { Calendar.current.startOfDay(for: $0.startDate) == day }) else { return }
        modelContext.insert(TrainingBlock(emphasis: emphasis, startDate: day))
        try? modelContext.save()
        #if DEBUG
            print("\(DebugTrace.prefix)[monthly_review] emphasis block inserted \(emphasis.rawValue) from \(day)")
        #endif
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

    /// Snapshot of the current live state for the pause/interruption overlays.
    /// nil when the session isn't in a pausable state.
    private func capturePausedFromState() -> WorkoutSessionState.PausedFromState? {
        switch sessionState {
        case let .warmup(ei, si):
            .warmup(exerciseIndex: ei, warmupSetIndex: si)
        case let .exercise(sub):
            .exercise(sub)
        case .cooldown:
            .cooldown
        default:
            nil
        }
    }

    /// Re-enter the state a pause/interruption captured, re-arming the right
    /// clock (warm-up move timer during warm-up; the elapsed clock otherwise).
    private func restore(_ previousState: WorkoutSessionState.PausedFromState) {
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

    func pause() {
        guard sessionState.isActive, let previousState = capturePausedFromState() else {
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

        restore(previousState)
    }

    // MARK: - Call Interruption (STATE_MACHINES §1 — interruptedCall)

    /// React to the phone-call state from the CXCallObserver. A connected or
    /// dialing call during a live session parks it in `.interruptedCall`; the
    /// call ending restores exactly the captured state. Everything else
    /// no-ops, so a call while idle/paused/summary never touches the session.
    func handleCallChange(callEnded: Bool) {
        if callEnded {
            guard case let .interruptedCall(previousState) = sessionState else {
                return
            }
            restore(previousState)
            HapticManager.notification(.warning)
        } else {
            guard sessionState.isActive, let previousState = capturePausedFromState() else {
                return
            }
            stopRestTimer()
            stopWarmupMoveTimer()
            stopElapsedTimer()
            sessionState = .interruptedCall(previousState: previousState)
        }
    }

    /// Live only while a session runs (armed in startWorkout, dropped in
    /// resetState) — no reason to observe the phone from the Today screen.
    private var callMonitor: CallInterruptionMonitor?

    func startCallMonitoring() {
        guard callMonitor == nil else {
            return
        }
        let monitor = CallInterruptionMonitor()
        monitor.onCallChange = { [weak self] ended in
            self?.handleCallChange(callEnded: ended)
        }
        callMonitor = monitor
    }

    func stopCallMonitoring() {
        callMonitor = nil
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

    // MARK: - Note signals (free-text feedback → prescription nudges)

    /// Coarse signals extracted from an exercise's recent free-text notes. Used
    /// to nudge the next prescription: conservative signals cap the weight, an
    /// "easy" signal nudges it up. PAIN DOMINATES — any pain note makes the
    /// exercise conservative regardless of an "easy" note elsewhere.
    struct NoteSignalSummary {
        var pain = false // injury/pain → hold conservative until it clears
        var tooHard = false // failed / too heavy / grind → hold conservative
        var tooEasy = false // too light / could do more → allow a nudge up
        var formIssue = false // form broke / sloppy → hold conservative

        /// Any signal that should PREVENT a weight increase this session.
        var isConservative: Bool { pain || tooHard || formIssue }

        /// OR another row's signals into this summary (an exercise's notes across
        /// several sets combine; any positive signal sticks).
        mutating func merge(_ other: NoteSignalSummary) {
            pain = pain || other.pain
            tooHard = tooHard || other.tooHard
            tooEasy = tooEasy || other.tooEasy
            formIssue = formIssue || other.formIssue
        }
    }

    // Pure keyword tables — immutable, so `nonisolated` lets the pure
    // `classifyNote` classifier read them off the main actor.

    /// Pain/injury keywords scanned in user notes. Lowercased, substring match.
    private nonisolated static let painKeywords = [
        "hurt", "pain", "painful", "tweak", "strain", "pinch", "pinched",
        "sore", "injury", "injured", "tendon", "ache", "aching", "sharp",
    ]

    /// "Too hard / failed" keywords → hold conservative next session.
    private nonisolated static let tooHardKeywords = [
        "too heavy", "too hard", "failed", "couldn't", "could not", "grind",
        "grinder", "grindy", "missed", "struggled", "barely", "way too heavy",
    ]

    /// Form-breakdown keywords → hold conservative next session.
    private nonisolated static let formIssueKeywords = [
        "form broke", "form broke down", "sloppy", "bad form", "lost form",
        "cheated", "cheat rep", "cheat reps",
    ]

    /// "Too easy / too light" keywords → nudge next session UP. Deliberately
    /// STRICT (explicit phrasing only) — bare "easy"/"light" false-trips
    /// ("easy on the knees", "light headed"), and this is the riskier upward
    /// direction, so we require the user to have clearly said it.
    private nonisolated static let tooEasyKeywords = [
        "too easy", "too light", "way too light", "way too easy",
        "felt too light", "could do more", "could've done more",
        "could have done more", "sandbagged", "sandbag", "left reps",
    ]

    /// Negators that cancel an "easy" match in the same note.
    private nonisolated static let easyNegators = ["not easy", "wasn't easy", "not light", "n't easy", "far from easy"]

    /// Classify a single already-lowercased note into coarse signals. Pure — the
    /// unit of the keyword logic, independently testable. Pain/too-hard/form all
    /// stack; "too easy" is dropped when a negator is present in the same note.
    nonisolated static func classifyNote(_ note: String) -> NoteSignalSummary {
        var s = NoteSignalSummary()
        if painKeywords.contains(where: { note.contains($0) }) {
            s.pain = true
        }
        if tooHardKeywords.contains(where: { note.contains($0) }) {
            s.tooHard = true
        }
        if formIssueKeywords.contains(where: { note.contains($0) }) {
            s.formIssue = true
        }
        if tooEasyKeywords.contains(where: { note.contains($0) }),
           !easyNegators.contains(where: { note.contains($0) }) {
            s.tooEasy = true
        }
        return s
    }

    /// Scan recent (last `days`) USER-PROVIDED SetFeedback notes and classify
    /// each exercise's free text into coarse prescription signals. Deterministic
    /// keyword matching — the honest floor, not full comprehension (that is the
    /// batched AI coach review's job). Transient (scanned fresh each call, no
    /// stored flag) so it always reflects the latest notes and adds no
    /// migration. Feedback whose plannedSet relationship is nil is skipped.
    func noteSignals(within days: Int = 21, modelContext: ModelContext) -> [UUID: NoteSignalSummary] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let descriptor = FetchDescriptor<SetFeedback>(
            predicate: #Predicate<SetFeedback> { $0.userProvidedFeedback && $0.capturedAt >= cutoff }
        )
        guard let rows = try? modelContext.fetch(descriptor) else {
            return [:]
        }
        var out: [UUID: NoteSignalSummary] = [:]
        for row in rows {
            // Read the denormalized exercise id — NEVER traverse row.plannedSet
            // here. That relationship is one-way and its .nullify does not fire,
            // so after a set is deleted it dangles and faults on invalidated
            // backing (crash). Rows captured before exerciseID existed read nil
            // and are simply skipped (they're old feedback, not a regression).
            guard let exID = row.exerciseID else {
                continue
            }
            guard let note = row.note?.lowercased(), !note.isEmpty else {
                continue
            }
            var summary = out[exID] ?? NoteSignalSummary()
            summary.merge(Self.classifyNote(note))
            out[exID] = summary
        }
        return out
    }

    /// Recently (last `days`) flagged exercise IDs — any USER-PROVIDED note
    /// mentioning pain. Thin wrapper over `noteSignals` (pain subset), kept for
    /// existing call sites.
    func painFlaggedExerciseIDs(within days: Int = 21, modelContext: ModelContext) -> Set<UUID> {
        Set(noteSignals(within: days, modelContext: modelContext).filter { $0.value.pain }.map(\.key))
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

    private func loadCustomWeekdayPlan(modelContext: ModelContext) -> [WorkoutType]? {
        let descriptor = FetchDescriptor<UserSettings>()
        return (try? modelContext.fetch(descriptor))?.first?.customWeekdayPlan
    }

    /// Internal (not private) — the ExercisePopulation extension reads the
    /// style for §19.3 volume/intensity application.
    func loadDeloadSettings(
        modelContext: ModelContext
    ) -> (frequency: Int, startDate: Date?, style: DeloadStyle, enabled: Bool) {
        let descriptor = FetchDescriptor<UserSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            let startDate = settings.userProfile?.createdAt
            return (
                frequency: settings.deloadFrequencyWeeks,
                startDate: startDate,
                style: settings.deloadStyle,
                enabled: settings.autoDeload
            )
        }
        return (frequency: 5, startDate: nil, style: .intensityCut, enabled: true)
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

// MARK: - CallInterruptionMonitor

/// NSObject shim between CXCallObserver and the @Observable view-model
/// (which can't be an NSObject delegate itself). Forwards only what the
/// session cares about: a call becoming live, or ending. Delegate callbacks
/// arrive on the main queue, so hopping to the main actor is assumption-safe.
@MainActor
private final class CallInterruptionMonitor: NSObject, CXCallObserverDelegate {
    private let observer = CXCallObserver()
    /// `true` = the call ended.
    var onCallChange: ((Bool) -> Void)?

    override init() {
        super.init()
        observer.setDelegate(self, queue: .main)
    }

    nonisolated func callObserver(_: CXCallObserver, callChanged call: CXCall) {
        let ended = call.hasEnded
        MainActor.assumeIsolated {
            onCallChange?(ended)
        }
    }
}
