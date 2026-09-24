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

    /// A session the user must be looking at: a live one (possibly started
    /// from the watch and adopted on load) or one awaiting resume/discard.
    var needsWorkoutScreen: Bool {
        isActive || self == .crashedRecovery
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
                    print(
                        "\(DebugTrace.prefix)[Workout] sessionState: \(oldValue) → \(sessionState) | exIdx=\(currentExerciseIndex) setIdx=\(currentSetIndex)"
                    )
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
        case .paused,
             .interruptedCall:
            return state(exerciseName: currentName, setText: setCountText, isPaused: true)
        case .cooldown:
            return state(exerciseName: "Cooldown", setText: "Almost done")
        case .idle,
             .summary,
             .saved,
             .discarded,
             .crashedRecovery:
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
    /// Today's FRESHLY generated template (before `mergePersistedIntoWeek`
    /// swaps in the persisted row). `ensureTodayPlanPersisted` compares the
    /// persisted row against THIS — comparing against the merged week meant
    /// comparing the row with itself, so a settings or trainer-program change
    /// could never replace a stale planned today.
    var todayTemplate: WorkoutPlan?
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
    /// The AI week call failed on network/server (not entitlement) — Week Plan
    /// is showing the standard plan and says so.
    var aiWeekUnavailable = false
    var aiWeekLastFailure: Date?

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
    let whoop: any WhoopServiceProtocol
    private let healthKit: any HealthKitServiceProtocol
    /// §5 calendar awareness — exams + day load into the daily prompt.
    /// Optional: paths that only ensure the plan (DailyResetCoordinator)
    /// don't need it; the picture just omits the calendar lines.
    let calendarService: (any CalendarServiceProtocol)?

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
        guard !isReloadInFlight else {
            return
        }
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
        // Already running (e.g. adopted on an earlier load / pull-to-refresh
        // mid-warmup) — don't re-adopt and reset the cursor and timers.
        if resolved.isCrashedInProgress, !sessionState.isActive {
            // §11 fix — WatchActionRouter.startWorkout() flips a plan to
            // `.inProgress` directly (it has no live TrainingViewModel to run
            // the real startWorkout() through), which looks identical here to
            // a genuine phone crash. Tell them apart: zero completed sets
            // means nothing was actually lost, so adopt it as a LIVE session
            // instead of showing "Resume your workout?" for a day that never
            // really started on the phone.
            if hasNoCompletedSets(resolved.plan) {
                adoptWatchStartedSession(resolved.plan)
            } else {
                sessionState = .crashedRecovery
            }
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
        // §11.14 — if the persisted session contradicts today's (re-resolved)
        // plan, drop it first and re-run FREE so the card matches the day.
        let staleSession = todayPlan
            .map { invalidateStaleDailySession(for: $0, modelContext: modelContext) } ?? false
        await runDailyReadinessSession(modelContext: modelContext, deterministicOnly: staleSession)

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
        // §6 — Monday-of-week via the locale-INDEPENDENT ISO 8601 calendar, not
        // `Calendar.current`. On an en_US device, `Calendar.current`'s own
        // dateComponents+weekday=2 math resolves "this Monday" to TOMORROW on a
        // Sunday (en_US's own week starts that Sunday, so weekday=2 is the day
        // after it) — which graded the wrong week and re-keyed on the wrong day.
        let thisMonday = TrainingCalendar.mondayOfWeek(containing: Date())
        let weekKey = AIProgramPlanner.isoDay(thisMonday)

        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)
        guard profile.lastOutcomeReviewWeekKey != weekKey else {
            return
        }

        guard let lastMonday = cal.date(byAdding: .day, value: -7, to: thisMonday),
              let lastSunday = cal.date(byAdding: .day, value: -1, to: thisMonday)
        else {
            return
        }
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
              let priorEnd = cal.date(byAdding: .day, value: -8, to: thisMonday)
        else {
            return
        }
        let priorWeekStart = cal.startOfDay(for: priorStart)
        let priorWeekEnd = cal.startOfDay(for: priorEnd)
        let priorRows = (try? modelContext.fetch(FetchDescriptor<ExerciseHistory>(
            predicate: #Predicate { $0.date >= priorWeekStart && $0.date <= priorWeekEnd }
        ))) ?? []
        let priorVolume = priorRows.reduce(0.0) { $0 + $1.totalVolume }

        // Planned training days last week = distinct non-rest gym days in the
        // current week template (a stable proxy for the cadence).
        let plannedTrainingDays = weekPlans.filter(\.type.isGymWorkout).count

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
            print(
                "\(DebugTrace.prefix)[outcome] week graded: quality=\(String(format: "%.2f", outcome.qualityScore)) hits=\(outcome.progressionHits) overreach=\(outcome.overreachEvents) missed=\(outcome.missedSessions)"
            )
        #endif
    }

    // MARK: - AI Week Hydration (Phase 2)

    /// Reconcile the deterministic week plan with an AI-proposed skeleton.
    /// No-ops when there's no API client (previews/tests/offline), when already
    /// run this week, or when a workout is in progress (never disturb a live
    /// session). All failures fall back to the deterministic plan silently.
    func hydrateWeekWithAI(modelContext: ModelContext) async {
        guard let apiClient else {
            return
        }
        guard !sessionState.isActive else {
            return
        }

        // §6 — locale-independent Monday (see runWeeklyOutcomeReview).
        let monday = TrainingCalendar.mondayOfWeek(containing: Date())
        let weekKey = AIProgramPlanner.isoDay(monday)

        // Once per ISO week (the Sonnet cost cap) — PERSISTED guard so a cold
        // start in the same week doesn't re-spend the call.
        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)
        guard profile.lastAIHydratedWeekKey != weekKey else {
            return
        }
        // A failed attempt retries at most hourly (not on every loadToday).
        if let lastFailure = aiWeekLastFailure, Date().timeIntervalSince(lastFailure) < 3600 {
            return
        }

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

        // A network/server failure leaves the week open for a later retry and
        // says so on Week Plan; a 402 (not Pro / no consent) or a real answer
        // marks the week done so it never re-spends the call.
        aiWeekUnavailable = result.failed
        if result.failed {
            aiWeekLastFailure = Date()
            return
        }
        aiWeekLastFailure = nil
        profile.lastAIHydratedWeekKey = weekKey
        try? modelContext.save()

        // Only mutate state if AI actually produced a reconciled plan.
        if result.rationale != nil {
            // §5 — `result.plans` are ALL fresh transient objects (the AI's
            // reconciled skeleton), so a wholesale reassignment here would undo
            // the persisted-row substitution `loadWeekPlan` just made for today
            // and any completed/in-progress day, silently un-checking them again.
            // Re-substitute on top of the AI's plans — every OTHER day keeps the
            // AI's in-place adjustment; only the sacred/live-today days are
            // swapped back to their persisted object.
            weekPlans = Self.mergePersistedIntoWeek(
                result.plans,
                persisted: persistedPlans(forWeekOf: monday, modelContext: modelContext),
                today: Date()
            )
            aiWeekRationale = result.rationale
        }
    }

    /// Last-7-day recovery scores (oldest→newest) for the AI program prompt.
    private func loadRecovery7DayTrend(modelContext: ModelContext) -> [Int] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: today) else {
            return []
        }
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= weekAgo },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.filter { $0.recoveryScore > 0 }.map { Int($0.recoveryScore.rounded()) }
    }

    /// §14 requirement (d) — the learned spare-day easy-modality cycle order,
    /// derived from what the user actually logged (manual completions AND Whoop
    /// imports both write canonical `WorkoutType` rawValues) over the trailing 4
    /// weeks. Runs vs swims decide which modality leads; the pure ranking lives in
    /// `TrainingEngine.easyModalityOrder`. Thin/balanced history → pool-first.
    private func learnedEasyModalityOrder(modelContext: ModelContext) -> [WorkoutType] {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -28, to: Date()) else {
            return [.pool, .run]
        }
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.date >= cutoff }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let pools = rows.filter { $0.workoutType == WorkoutType.pool.rawValue }.count
        let runs = rows.filter { $0.workoutType == WorkoutType.run.rawValue }.count
        return TrainingEngine.easyModalityOrder(poolLogged: pools, runLogged: runs)
    }

    /// Result of resolving today's plan — the persisted WorkoutPlan plus
    /// whether it's a crashed in-progress session the caller must restore.
    struct ResolvedTodayPlan {
        let plan: WorkoutPlan
        let isCrashedInProgress: Bool
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
           )
        {
            for plan in plans where plan.type.isGymWorkout {
                plan.type = .mobility
                plan.notes = "Deload — full rest week. Move, stretch, recover."
            }
        }

        // The athlete's own trainer program replaces the generated gym days
        // (recovery + match days still adjust it — see +TrainerProgram).
        if let program = activeTrainerProgram(modelContext: modelContext) {
            Self.applyTrainerProgram(program, to: plans, matchDayKeys: matchDayKeys)
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

    /// Read-only snapshot of the real ISO week containing `date`, built from
    /// the EXACT SAME generation path `loadWeekPlan` uses (assembleWeekPlans:
    /// split, custom weekday map, recovery, matches, emphasis, deload, and the
    /// TrainerProgram overlay) with the persisted-row substitution for today
    /// and any sacred (completed/in-progress) day, so it can never disagree
    /// with what the Training tab actually shows. Unlike `loadWeekPlan`, this
    /// does NOT mutate instance state (`weekPlans`, `todayTemplate`, deload
    /// flags) and does NOT populate exercises — callers that only need "what
    /// TYPE of training happens on each day" (e.g. `TrainingScheduleProvider`
    /// for Nutrition) can call this on a throwaway TrainingViewModel without
    /// disturbing a live session, exactly like `DailyResetCoordinator
    /// .workoutPlanEnsurer` already does for `ensureTodayPlanPersisted`.
    func weekPlanSnapshot(containing date: Date, modelContext: ModelContext) -> [WorkoutPlan] {
        let monday = TrainingCalendar.mondayOfWeek(containing: date)
        let generated = assembleWeekPlans(
            startingMonday: monday,
            modelContext: modelContext,
            referenceDate: date
        )
        let persisted = persistedPlans(forWeekOf: monday, modelContext: modelContext)
        return Self.mergePersistedIntoWeek(generated, persisted: persisted, today: date)
    }

    func loadWeekPlan(modelContext: ModelContext) {
        let today = Date()
        // §6 — locale-independent Monday (see runWeeklyOutcomeReview): a
        // `Calendar.current` computation here mis-anchored the whole week on an
        // en_US Sunday.
        let monday = TrainingCalendar.mondayOfWeek(containing: today)

        let generated = assembleWeekPlans(
            startingMonday: monday,
            modelContext: modelContext,
            referenceDate: today
        )

        // §5 — `assembleWeekPlans` always builds FRESH transient WorkoutPlan
        // objects, while `todayPlan` (and any completed/in-progress day) is the
        // PERSISTED row (ensureTodayPlanPersisted). Substitute the persisted
        // object in wherever one exists for today or a sacred (completed/
        // in-progress) day, so Week Plan, Today and the Dashboard Move quadrant
        // all read the exact same object/state — without this, every reload
        // re-rolled today's exercises back to .planned and a completed day lost
        // its checkmark.
        todayTemplate = generated.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
        weekPlans = Self.mergePersistedIntoWeek(
            generated,
            persisted: persistedPlans(forWeekOf: monday, modelContext: modelContext),
            today: today
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

        // Populate exercises for each gym workout. No-ops for a substituted
        // persisted plan that already carries its exercises (populateExercises
        // guards on `orderedExercises.isEmpty`).
        for plan in weekPlans {
            populateExercises(for: plan, modelContext: modelContext)
        }
    }

    /// Persisted WorkoutPlan rows already on disk for the week starting
    /// `monday` — the input `mergePersistedIntoWeek` substitutes into the
    /// freshly generated (transient) week template. See `loadWeekPlan`.
    private func persistedPlans(forWeekOf monday: Date, modelContext: ModelContext) -> [WorkoutPlan] {
        let cal = Calendar.current
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: monday) else {
            return []
        }
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { $0.date >= monday && $0.date < weekEnd }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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
        // §11.14 — the schedule edit may have just changed today's TYPE while
        // the coach's persisted session still describes the old day. Drop the
        // stale card and re-run the coach deterministically (free) so the
        // header and the card can never contradict each other.
        if invalidateStaleDailySession(for: resolved.plan, modelContext: modelContext) {
            Task { @MainActor in
                await runDailyReadinessSession(modelContext: modelContext, deterministicOnly: true)
            }
        }
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

    /// True when a plan has logged zero sets — used in `loadToday` to tell a
    /// genuine phone crash (real progress at risk) apart from a plan
    /// `WatchActionRouter.startWorkout()` flipped to `.inProgress` before the
    /// phone ever opened a live session (§11). Internal (not private) so it's
    /// directly unit-testable without driving the whole async `loadToday`
    /// pipeline.
    func hasNoCompletedSets(_ plan: WorkoutPlan) -> Bool {
        !plan.orderedExercises.contains { ex in ex.orderedSets.contains { $0.completed } }
    }

    /// Bring a watch-started session (plan already `.inProgress`, nothing
    /// logged yet) onto the phone as a genuinely LIVE session — the same
    /// shape `startWorkout()` leaves one in, minus re-flipping `plan.status`
    /// / re-stamping `startedAt` (the watch already did both). §11 fix: this
    /// is what lets `loadToday` skip `.crashedRecovery` for a session that
    /// never actually crashed. Internal (not private) for the same testing
    /// reason as `hasNoCompletedSets`.
    func adoptWatchStartedSession(_ plan: WorkoutPlan) {
        currentExerciseIndex = 0
        currentSetIndex = 0
        detectedPRs = []
        startCallMonitoring()
        if plan.type.isGymWorkout {
            warmupRoutine = WarmupRoutine.routine(for: plan.type)
            warmupMoveIndex = 0
            Self.activateRestAudioSession()
            sessionState = .warmup(exerciseIndex: 0, warmupSetIndex: 0)
            startWarmupMoveTimerForCurrent()
        } else {
            let startedAt = plan.startedAt ?? Date()
            workoutStartTime = startedAt
            elapsedSeconds = Date().timeIntervalSince(startedAt)
            sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))
            startElapsedTimer()
        }
        startLiveActivity()
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
            // §3 fix — a plan with zero exercises has nothing to warm up
            // into. `.cooldown` used to render a blank screen here
            // (ActiveWorkoutView has no case for it); go straight to the
            // summary, matching recoverFromEmptyExercise's own terminal path.
            sessionState = .summary
            return
        }
        let sets = first.orderedSets
        let firstWorkingIndex = sets.firstIndex { !$0.isWarmup } ?? 0
        #if DEBUG
            print(
                "\(DebugTrace.prefix)[Workout] advancePastWarmup: totalSets=\(sets.count) warmups=\(sets.filter(\.isWarmup).count) → firstWorkingIndex=\(firstWorkingIndex)"
            )
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
        // §11.13 — never land on an exercise with no sets (Finish Set would
        // have nothing to log and the session would freeze).
        if sets.isEmpty {
            recoverFromEmptyExercise(startingAt: 0)
        } else {
            sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: firstWorkingIndex))
        }
    }

    /// §11.13 — a planned exercise can arrive with ZERO sets (corrupted or
    /// legacy rows). Landing on one froze the session: Finish Set and Skip
    /// had nothing to act on and silently returned. Jump to the next exercise
    /// that still has an uncompleted set, or wrap the session when none does.
    func recoverFromEmptyExercise(startingAt startIndex: Int? = nil) {
        guard let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises
        var idx = startIndex ?? (currentExerciseIndex + 1)
        while idx < exercises.count {
            if let setIdx = firstUncompletedSetIndex(in: exercises[idx]) {
                currentExerciseIndex = idx
                currentSetIndex = setIdx
                sessionState = .exercise(.setActive(exerciseIndex: idx, setIndex: setIdx))
                return
            }
            idx += 1
        }
        stopElapsedTimer()
        sessionState = .summary
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

        guard foundActiveExercise else {
            // §3 fix — every exercise is already complete (or the plan holds
            // none): there's nothing left to resume into. `.cooldown` used to
            // render a blank screen here; go straight to the summary instead
            // of starting timers/monitoring for a session that's already done.
            sessionState = .summary
            return
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
            // §11.13 — an empty exercise means the tap must MOVE the session,
            // not silently die.
            if sets.isEmpty {
                recoverFromEmptyExercise()
            }
            return
        }

        let set = sets[currentSetIndex]
        // §11 fix — the watch can complete this exact set (routed through
        // this same function — see TrainingViewModel+WatchSync.applyWatchSetLog)
        // moments before a phone tap lands on a UI that hadn't re-rendered
        // yet. Logging again here would silently overwrite the watch's real
        // numbers with whatever's sitting in the phone's stale input fields.
        guard !set.completed else {
            #if DEBUG
                print(
                    "\(DebugTrace.prefix)[Workout] logSet: set already completed (exIdx=\(currentExerciseIndex) setIdx=\(currentSetIndex)) — ignoring stale tap"
                )
            #endif
            return
        }
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
        saveGuarded(modelContext, operation: "set")

        // PR detection — working sets only. Warmup ramp sets must never trigger
        // a PR (this is why duplicate/low PRs appeared, e.g. two "Face Pull" PRs:
        // the warmup set and the working set each fired). A drop step (§6.4) is
        // excluded too — a reduced-weight backoff set is never a max-effort
        // signal, so it can never legitimately BE the PR.
        if !set.isWarmup, !set.isDropStep, let exercise = plannedExercise.exercise {
            if let pr = trainingEngine.detectPersonalRecord(
                exercise: exercise,
                weight: weight,
                reps: reps,
                workoutPlanID: plan.id // §13 fix — stamp so history-delete can match this PR exactly
            ) {
                modelContext.insert(pr)
                saveGuarded(modelContext, operation: "PR")
                detectedPRs.append(pr)
                HapticManager.notification(.success)
            }
        }

        // Determine next state
        let isLastSet = currentSetIndex >= sets.count - 1
        let isLastExercise = currentExerciseIndex >= exercises.count - 1
        #if DEBUG
            let warmupCount = sets.filter(\.isWarmup).count
            print(
                "\(DebugTrace.prefix)[Workout] logSet: exIdx=\(currentExerciseIndex)/\(exercises.count) setIdx=\(currentSetIndex)/\(sets.count) (warmups=\(warmupCount)) → isLastSet=\(isLastSet) isLastExercise=\(isLastExercise)"
            )
        #endif

        // §6.4/§7.7 drop sets — a queued drop step right after this set
        // continues immediately with NO rest, in the same set-active flow.
        // Takes priority over circuit rotation below: a drop chain is never
        // interrupted by a partner exercise.
        if currentSetIndex + 1 < sets.count, sets[currentSetIndex + 1].isDropStep {
            currentSetIndex += 1
            sessionState = .exercise(.setActive(
                exerciseIndex: currentExerciseIndex, setIndex: currentSetIndex
            ))
            HapticManager.selection()
            return
        }

        // §6.1-6.3 superset/circuit rotation — A1 → B1 → C1 … with NO rest
        // between members, then the group's ONE shared rest before the next
        // round: A2 → B2 → C2 … Warmup ramps stay in the normal per-exercise
        // flow; rotation starts at the first working set. `circuitMembers`
        // generalizes the old adjacent-PAIR lookup to 2..N members, so a
        // 2-exercise superset is just the N=2 case of the same rotation.
        if !set.isWarmup {
            let members = circuitMembers(of: currentExerciseIndex)
            if members.count > 1 {
                let isLastOfRotation = isLastOfCircuitRotation(currentExerciseIndex)

                if let next = nextCircuitMemberWithWork(after: currentExerciseIndex) {
                    if !isLastOfRotation {
                        // Any member except the round's last → straight into
                        // the next member, no rest.
                        currentExerciseIndex = next.exerciseIndex
                        currentSetIndex = next.setIndex
                        sessionState = .exercise(.setActive(
                            exerciseIndex: next.exerciseIndex, setIndex: next.setIndex
                        ))
                        HapticManager.selection()
                        return
                    }
                    // The round's last member → the group's one shared rest,
                    // then continue the rotation from the first member with work.
                    restOrJump(to: next.exerciseIndex, setIndex: next.setIndex, after: plannedExercise)
                    return
                }
                if members.allSatisfy({ firstUncompletedSetIndex(in: exercises[$0]) == nil }) {
                    // Whole group fully logged → advance PAST every member
                    // (the standard next-exercise path would land on an
                    // already-finished partner).
                    let afterGroup = (members.max() ?? currentExerciseIndex) + 1
                    if afterGroup >= exercises.count {
                        stopElapsedTimer()
                        sessionState = .summary
                    } else {
                        restOrJump(to: afterGroup, setIndex: 0, after: plannedExercise)
                    }
                    return
                }
                // Every other member is done, this lift still has sets →
                // finish it in the standard flow below.
            }
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

    // MARK: - Skip set / warmup (§2.16)

    /// Skip the current set without logging it. The set is REMOVED from the
    /// plan — an unperformed set must not linger uncompleted (the superset
    /// flow would loop back to it and the completion ring could never
    /// close). No rest starts: skipping isn't work.
    func skipCurrentSet(modelContext: ModelContext) {
        guard case .exercise(.setActive) = sessionState, let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return
        }
        let slot = exercises[currentExerciseIndex]
        let sets = slot.orderedSets
        guard currentSetIndex < sets.count, !sets[currentSetIndex].completed else {
            // §11.13 — same self-heal as logSet: an empty exercise moves on.
            if sets.isEmpty {
                recoverFromEmptyExercise()
            }
            return
        }
        modelContext.delete(sets[currentSetIndex])
        saveGuarded(modelContext, operation: "skipped set")
        advanceAfterSkip(in: slot, plan: plan)
    }

    /// One tap drops the exercise's remaining warmup ramp ("already warm")
    /// and lands on the first working set.
    func skipRemainingWarmups(modelContext: ModelContext) {
        guard case .exercise(.setActive) = sessionState, let plan = todayPlan else {
            return
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return
        }
        let slot = exercises[currentExerciseIndex]
        let doomed = slot.orderedSets.filter { $0.isWarmup && !$0.completed }
        guard !doomed.isEmpty else {
            return
        }
        for set in doomed {
            modelContext.delete(set)
        }
        saveGuarded(modelContext, operation: "warm-up skip")
        advanceAfterSkip(in: slot, plan: plan)
    }

    /// Land on the next real work after a skip: same exercise's next
    /// uncompleted set, else the next circuit member's (§6.3 — generalizes
    /// the old pair-only partner lookup to 2..N members), else the next
    /// exercise that still has one, else summary. Mirrors logSet's routing
    /// minus the rest timer.
    private func advanceAfterSkip(in slot: PlannedExercise, plan: WorkoutPlan) {
        let exercises = plan.orderedExercises
        if let next = firstUncompletedSetIndex(in: slot) {
            currentSetIndex = next
            sessionState = .exercise(.setActive(
                exerciseIndex: currentExerciseIndex, setIndex: next
            ))
            HapticManager.selection()
            return
        }
        if let next = nextCircuitMemberWithWork(after: currentExerciseIndex) {
            currentExerciseIndex = next.exerciseIndex
            currentSetIndex = next.setIndex
            sessionState = .exercise(.setActive(
                exerciseIndex: next.exerciseIndex, setIndex: next.setIndex
            ))
            HapticManager.selection()
            return
        }
        var candidate = currentExerciseIndex + 1
        while candidate < exercises.count {
            if let setIdx = firstUncompletedSetIndex(in: exercises[candidate]) {
                currentExerciseIndex = candidate
                currentSetIndex = setIdx
                sessionState = .exercise(.setActive(
                    exerciseIndex: candidate, setIndex: setIdx
                ))
                HapticManager.selection()
                return
            }
            candidate += 1
        }
        stopElapsedTimer()
        sessionState = .summary
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
        saveGuarded(modelContext, operation: "set feedback")

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

    // MARK: - Superset / Circuit Flow (§6 / §2.8 / §6.3)

    //
    // Circuit membership (`circuitMembers`), rotation helpers, and the
    // active-screen group label live in TrainingViewModel+Groups.swift —
    // pulled out to keep this file under the length guard. `logSet` and
    // `advanceAfterSkip` below call into them directly (same target, no
    // import needed).

    func firstUncompletedSetIndex(in plannedExercise: PlannedExercise) -> Int? {
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
                    // §11.13 — the next slot may hold no sets; land on the
                    // first one that does instead of freezing there.
                    if exercises[nextIndex].orderedSets.isEmpty {
                        recoverFromEmptyExercise(startingAt: nextIndex)
                    } else {
                        currentExerciseIndex = nextIndex
                        currentSetIndex = 0
                        sessionState = .exercise(.setActive(
                            exerciseIndex: nextIndex,
                            setIndex: 0
                        ))
                    }
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

    /// Whether today's plan has at least one completed WORKING (non-warmup)
    /// set — the bar for "actually did something". §3 fix: a Finish with
    /// nothing logged must not mint a phantom `.inProgress` plan that can
    /// never be regenerated (persistCompletion's own zero-sets guard leaves
    /// status exactly where it found it, so nothing else ever reverts it).
    private var hasAnyCompletedWorkingSet: Bool {
        guard let plan = todayPlan else {
            return false
        }
        return plan.orderedExercises.contains { ex in
            ex.orderedSets.contains { $0.completed && !$0.isWarmup }
        }
    }

    /// Finish the session early (user tapped Finish before all sets). Saving is
    /// the caller's choice — see `discardActiveWorkout`. This path goes straight
    /// to the summary (no cooldown screen); persistCompletion (fired on .summary
    /// entry by the tab) saves only the working sets actually logged.
    ///
    /// §3 fix — guarded per-state: `.crashedRecovery` has no restored
    /// elapsed/duration to save (that needs `resumeFromCrash`'s timing
    /// restore first) and every other non-live state is already past this
    /// point, so this used to be reachable from anywhere via the toolbar's
    /// unconditional Finish button. A zero-working-set finish (e.g. tapped
    /// from `.warmup`) is routed to the SAME rollback `discardActiveWorkout`
    /// does instead of leaving the day wedged `.inProgress` forever.
    func finishWorkout(modelContext: ModelContext) {
        switch sessionState {
        case .warmup,
             .exercise,
             .cooldown,
             .paused:
            break
        default:
            return
        }
        guard hasAnyCompletedWorkingSet else {
            discardActiveWorkout(modelContext: modelContext)
            return
        }
        stopRestTimer()
        stopWarmupMoveTimer()
        stopElapsedTimer()
        sessionState = .summary
    }

    /// Discard the in-progress session: restore the plan to `.planned`, roll
    /// back any sets logged THIS session WITHOUT writing ExerciseHistory, and
    /// reset. The day stays open to redo. Used by the Finish → "Discard"
    /// choice, and by `finishWorkout` when nothing was actually logged.
    ///
    /// §3 fix — now also valid from `.interruptedCall` and `.crashedRecovery`
    /// (previously a silent no-op there, e.g. if the toolbar's Finish/Discard
    /// flow was reached while a crash-recovery prompt was up).
    func discardActiveWorkout(modelContext: ModelContext) {
        switch sessionState {
        case .warmup,
             .exercise,
             .cooldown,
             .paused,
             .interruptedCall,
             .crashedRecovery:
            break
        default:
            return
        }
        // Full teardown (timers + call monitor + cursor) — this now also
        // covers `.crashedRecovery`, which needs the SAME complete reset
        // `discardCrashedWorkout` already does, not just the timer stops the
        // live-session path used to settle for.
        resetState()
        if let plan = todayPlan {
            // Roll back this session's logged sets so a re-do starts clean.
            // Keep the plan .planned (NOT .skipped/.completed) so the day stays
            // OPEN TO REDO, exactly as the dialog promises — and writes no
            // ExerciseHistory.
            var rolledBackSetIDs: Set<UUID> = []
            for ex in plan.orderedExercises {
                for set in ex.orderedSets where set.completed {
                    rolledBackSetIDs.insert(set.id)
                    set.completed = false
                    set.actualWeight = nil
                    set.actualReps = nil
                    set.completedAt = nil
                }
            }
            plan.status = .planned
            plan.startedAt = nil
            // A rolled-back set's SetFeedback row would otherwise linger and
            // shadow the redo (the inline panel would show stale RPE/notes
            // from the discarded attempt on the very first re-log).
            if !rolledBackSetIDs.isEmpty {
                let allFeedback = (try? modelContext.fetch(FetchDescriptor<SetFeedback>())) ?? []
                for feedback in allFeedback where rolledBackSetIDs.contains(feedback.setID) {
                    modelContext.delete(feedback)
                }
            }
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
        saveErrorMessage = "Couldn't save your \(operation). Try it again — if this keeps happening, free up iPhone storage."
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
            guard let exercise = plannedEx.exercise else {
                return nil
            }
            let completedSets = (plannedEx.sets ?? []).filter { $0.completed && !$0.isWarmup }
            guard !completedSets.isEmpty else {
                return nil
            }
            let totalVolume = completedSets.reduce(0.0) { acc, set in
                guard let w = set.actualWeight, let r = set.actualReps else {
                    return acc
                }
                return acc + (w * Double(r))
            }
            // §6.4 — a drop step is a reduced-weight backoff, never the
            // session's "best" set; volume/set-count above still count it
            // (the work was performed), but the history's headline
            // weight/reps must come from a real working set.
            let best = completedSets
                .filter { !$0.isDropStep }
                .max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) }

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
            print(
                "\(DebugTrace.prefix)[Workout] persistCompletion: plan=\(planID) wrote \(snapshots.count) history rows, status=.completed"
            )
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
        guard saveErrorMessage == nil else {
            return
        }

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
            print(
                "\(DebugTrace.prefix)[Workout] persistNonGymCompletion: plan=\(planID) type=\(plan.type.rawValue) source=\(session.source) strain=\(session.strain.map { String($0) } ?? "nil")"
            )
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
        guard (1 ... 10).contains(rpe) else {
            return
        }
        guard let plan = todayPlan, plan.status == .completed else {
            return
        }
        plan.sessionRPE = rpe
        // Denormalize onto the linked session so the accuracy spine never has to
        // traverse the one-way `.nullify` link (dangling-crash guard — see
        // DailySession.actualSessionRPE). dailySession is today's 1:1 pair.
        dailySession?.actualSessionRPE = rpe
        saveGuarded(modelContext, operation: "session RPE")
        #if DEBUG
            print(
                "\(DebugTrace.prefix)[Workout] recordSessionRPE: plan=\(plan.id) rpe=\(rpe) expected=\(dailySession?.expectedSessionRPE.map(String.init) ?? "nil")"
            )
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
              let stashed = plan.plannedTypeRaw
        else {
            return
        }
        plan.typeRaw = stashed
        plan.plannedTypeRaw = nil
        dailySession?.userOverrode = true
        saveGuarded(modelContext, operation: "workout choice")
        // Watch + Dashboard read the persisted plan directly — without this
        // they keep showing the coach's move until their next unrelated reload.
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
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
        guard let plan = todayPlan, plan.isTwoADay, let second = plan.secondarySessionType else {
            return
        }
        plan.secondaryCompleted.toggle()

        let planID = plan.id
        let typeRaw = second.rawValue
        // The cardio's own ActivitySession, keyed (planID, type) so it's found on
        // undo. The gym lift writes ExerciseHistory (not ActivitySession), so this
        // is the ONLY ActivitySession for the plan — no collision with the lift.
        let existing = (try? modelContext.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate<ActivitySession> { $0.workoutPlanID == planID && $0.workoutType == typeRaw }
        ))) ?? []
        for row in existing {
            modelContext.delete(row)
        } // dedup / undo both start clean

        if plan.secondaryCompleted {
            let cardio = ActivitySession(
                date: Date(), startTime: Date(), workoutType: typeRaw, sportID: -1,
                source: "manual", workoutPlanID: planID,
                strain: nil, averageHeartRate: nil, maxHeartRate: nil,
                caloriesBurned: nil, durationMinutes: 30
            )
            modelContext.insert(cardio)
        }
        saveGuarded(modelContext, operation: "second session")

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
            print(
                "\(DebugTrace.prefix)[daily_coach] two-a-day second session → \(plan.secondaryCompleted ? "done (logged \(typeRaw))" : "undone (removed)")"
            )
        #endif
    }

    // MARK: - Monthly Review (D4 §17) — methods in TrainingViewModel+MonthlyReview.swift

    /// Month key with a review currently due (drives the Training-tab card).
    /// Set by loadToday; nil outside the window or once the summary exists.
    var monthlyReviewDueKey: String?

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
        // Watch + Dashboard read the plan's exercise order too.
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
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
            // A user-added set inherits the effort target of the set it clones.
            targetRIR: lastSet?.targetRIR,
            plannedExercise: plannedExercise
        )

        if plannedExercise.sets != nil {
            plannedExercise.sets?.append(newSet)
        } else {
            plannedExercise.sets = [newSet]
        }

        saveGuarded(modelContext, operation: "added set")
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
            saveGuarded(modelContext, operation: "set change")
            HapticManager.selection()
        }
    }

    // Drop-set logging (§6.4/§7.7) and manual group control (§6.5) live in
    // TrainingViewModel+Groups.swift, alongside the circuit helpers above.

    // MARK: - Pause / Resume / Call Interruption

    // Pause/resume, call-interruption handling, and the rest-timer-remaining
    // capture that makes both of them restart a mid-rest countdown correctly
    // (§2) live in TrainingViewModel+PauseResume.swift — split out to keep
    // this file under the SwiftLint length caps. The two stored properties
    // below stay here (extensions can't add stored properties); they're
    // internal, not private, so that file can reach them.

    /// Remaining rest-timer seconds captured at the moment a pause/call
    /// interruption caught the session mid-rest (§2 / STATE_MACHINES §1).
    /// `stopRestTimer()` (called right after) zeroes `restEndDate`, so this
    /// is the ONLY place the real remaining time survives — `restore()`
    /// reads it to restart the rest timer instead of leaving RestTimerView
    /// frozen at 0:00 forever. nil when the interruption wasn't mid-rest.
    var pausedRestRemaining: TimeInterval?

    /// Live only while a session runs (armed in startWorkout, dropped in
    /// resetState) — no reason to observe the phone from the Today screen.
    var callMonitor: CallInterruptionMonitor?

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

    // MARK: - User Settings Loaders

    func loadFootballDays(modelContext: ModelContext) -> ActiveDays {
        let descriptor = FetchDescriptor<UserSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            return settings.footballDays
        }
        return ActiveDays(rawValue: 0) // no football days
    }

    func loadTrainingSplit(modelContext: ModelContext) -> TrainingSplit {
        let descriptor = FetchDescriptor<UserSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            return settings.trainingSplit
        }
        return .pushPullLegs // default
    }

    func loadCustomWeekdayPlan(modelContext: ModelContext) -> [WorkoutType]? {
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

    func loadRecoveryScore(modelContext: ModelContext) -> Double? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date == today },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        // A 0 row is the Recovery tab's no-data placeholder (Whoop never
        // reports 0) — unknown, never "red".
        guard let score = try? modelContext.fetch(descriptor).first?.recoveryScore, score > 0 else {
            return nil
        }
        return score
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
        guard let rows = try? modelContext.fetch(descriptor) else {
            return [:]
        }
        var result: [Date: Double] = [:]
        for row in rows where row.recoveryScore > 0 { // 0 = no data, not red
            let key = cal.startOfDay(for: row.date)
            result[key] = row.recoveryScore
        }
        return result
    }
}
