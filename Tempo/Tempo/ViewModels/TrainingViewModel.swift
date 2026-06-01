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
    private var restTimerTask: Task<Void, Never>?
    /// Wall-clock instant the current rest period completes. The timer is
    /// anchored to this Date (not a per-tick decrement) so it stays correct
    /// when the app is backgrounded and the driving Task is suspended.
    private var restEndDate: Date?
    /// Highest integer second for which a countdown cue has already fired,
    /// so re-syncing on foreground does not replay cues. Starts at Int.max.
    private var lastCuedSecond: Int = Int.max

    // MARK: - Guided Warm-Up

    /// The resolved routine for today's workout, shown in the guided warm-up.
    var warmupRoutine: WarmupRoutine?
    /// Index of the move the user is currently on in the guided warm-up.
    var warmupMoveIndex: Int = 0
    /// Remaining seconds on the current TIMED warm-up move (0 for rep-based).
    var warmupMoveRemaining: TimeInterval = 0
    /// Wall-clock end instant for the current timed warm-up move — Date-anchored
    /// exactly like the rest timer so it survives backgrounding (the user walks
    /// around the gym during warm-up).
    private var warmupMoveEndDate: Date?
    private var warmupMoveTask: Task<Void, Never>?

    // MARK: - Elapsed Timer

    private var elapsedTimerTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let trainingEngine: any TrainingEngineProtocol
    private let whoop: any WhoopServiceProtocol
    private let healthKit: any HealthKitServiceProtocol

    // MARK: - Init

    init(
        trainingEngine: any TrainingEngineProtocol,
        whoop: any WhoopServiceProtocol,
        healthKit: any HealthKitServiceProtocol
    ) {
        self.trainingEngine = trainingEngine
        self.whoop = whoop
        self.healthKit = healthKit
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

        // Check deload week status
        let deloadSettings = loadDeloadSettings(modelContext: modelContext)
        isDeloadWeek = trainingEngine.isDeloadWeek(
            date: Date(),
            deloadFrequencyWeeks: deloadSettings.frequency,
            trainingStartDate: deloadSettings.startDate
        )

        isLoading = false
    }

    /// Result of resolving today's plan — the persisted WorkoutPlan plus
    /// whether it's a crashed in-progress session the caller must restore.
    struct ResolvedTodayPlan {
        let plan: WorkoutPlan
        let isCrashedInProgress: Bool
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
            if existing.status == .planned,
               let canonical = weekPlanForToday, canonical.type != existing.type {
                // Only a still-PLANNED row may be replaced when it disagrees
                // with the Week Plan (e.g. user changed Football Days, or it
                // was a stale row). A completed or in-progress plan is sacred —
                // it records what was actually trained, so it survives even if
                // its type no longer matches the forward-looking template.
                // Deleting it here was a data-loss path (orphaned its history).
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

        weekPlans = trainingEngine.generateWeekPlan(
            startDate: monday,
            recoveryScores: recoveryScores,
            footballDays: footballDays,
            split: split
        )

        // Check deload week status
        let deloadSettings = loadDeloadSettings(modelContext: modelContext)
        isDeloadWeek = trainingEngine.isDeloadWeek(
            date: Date(),
            deloadFrequencyWeeks: deloadSettings.frequency,
            trainingStartDate: deloadSettings.startDate
        )

        // Populate exercises for each gym workout
        for plan in weekPlans {
            populateExercises(for: plan, modelContext: modelContext)
        }
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
            // Per STATE_MACHINES.md — last set of last exercise → cooldown
            sessionState = .cooldown
            stopElapsedTimer()
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
    }

    // MARK: - Skip Rest

    func skipRest() {
        stopRestTimer()
        advanceAfterRest()
    }

    // MARK: - Advance After Rest

    private enum RestNextAction {
        case nextSet
        case nextExercise
    }

    private var pendingRestAction: RestNextAction = .nextSet

    private func advanceAfterRest() {
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
                sessionState = .cooldown
            }
            HapticManager.notification(.warning)
        }
    }

    // MARK: - Finish Workout (manual)

    // Per STATE_MACHINES.md — any active state → cooldown → summary

    func finishWorkout() {
        stopRestTimer()
        stopElapsedTimer()
        sessionState = .cooldown

        // Auto-advance to summary after a brief delay
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            sessionState = .summary
        }
    }

    // MARK: - Skip Cooldown → Summary

    func skipCooldown() {
        sessionState = .summary
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
        struct HistorySnapshot {
            let exercise: Exercise
            let totalVolume: Double
            let best1RM: Double?
            let bestSetWeight: Double?
            let bestSetReps: Int?
            let setsPerformed: Int
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
            return HistorySnapshot(
                exercise: exercise,
                totalVolume: totalVolume,
                best1RM: completedSets.compactMap(\.estimated1RM).max(),
                bestSetWeight: best?.actualWeight,
                bestSetReps: best?.actualReps,
                setsPerformed: completedSets.count
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
                workoutPlanID: planID,
                exercise: snap.exercise
            )
            modelContext.insert(history)
        }

        // Persist to SwiftData
        try? modelContext.save()
        #if DEBUG
            print("\(DebugTrace.prefix)[Workout] persistCompletion: plan=\(planID) wrote \(snapshots.count) history rows, status=.completed")
        #endif

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

    // Per MODULE_TRAINING.md Section 2 — Display values

    var currentExercise: PlannedExercise? {
        guard let plan = todayPlan else {
            return nil
        }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else {
            return nil
        }
        return exercises[currentExerciseIndex]
    }

    var currentSet: PlannedSet? {
        guard let exercise = currentExercise else {
            return nil
        }
        let sets = exercise.orderedSets
        guard currentSetIndex < sets.count else {
            return nil
        }
        return sets[currentSetIndex]
    }

    var totalExercises: Int {
        todayPlan?.orderedExercises.count ?? 0
    }

    var totalSets: Int {
        todayPlan?.totalSets ?? 0
    }

    var completedSets: Int {
        todayPlan?.completedSets ?? 0
    }

    var totalVolume: Double {
        todayPlan?.totalVolume ?? 0
    }

    var formattedVolume: String {
        // totalVolume is kg-stored; show in the user's unit.
        let vol = WeightUnit.kg.convert(totalVolume, to: weightUnit)
        let unit = weightUnit.abbreviation
        if vol >= 1000 {
            return String(format: "%.1fk %@", vol / 1000, unit)
        }
        return "\(Int(vol)) \(unit)"
    }

    /// Working-set count for the current exercise (excludes warmup) so the
    /// +/- stepper matches the "Set X of N" header.
    var workingSetCount: Int {
        (currentExercise?.orderedSets ?? []).filter { !$0.isWarmup }.count
    }

    var formattedElapsedTime: String {
        let total = Int(elapsedSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedRestTimer: String {
        let remaining = Int(restTimerRemaining)
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var restTimerProgress: Double {
        guard restTimerTotal > 0 else {
            return 0
        }
        return 1.0 - (restTimerRemaining / restTimerTotal)
    }

    var setCountText: String {
        guard let exercise = currentExercise else {
            return ""
        }
        let sets = exercise.orderedSets
        let total = sets.count

        // Indicate if current set is a warmup
        if currentSetIndex < sets.count, sets[currentSetIndex].isWarmup {
            let warmupCount = sets.filter(\.isWarmup).count
            let warmupIndex = sets.prefix(currentSetIndex + 1).filter(\.isWarmup).count
            return "Warmup \(warmupIndex) of \(warmupCount)"
        }

        let workingSets = sets.filter { !$0.isWarmup }
        let workingIndex = currentSetIndex - sets.filter(\.isWarmup).count + 1
        if workingSets.count < total {
            return "Set \(workingIndex) of \(workingSets.count)"
        }
        return "Set \(currentSetIndex + 1) of \(total)"
    }

    /// Context for the rest screen: what the user is resting *toward*.
    /// During between-sets rest this is the current exercise; during the rest
    /// before the next exercise it is the upcoming exercise (so the screen can
    /// preview its name + how-to instead of mislabelling it "Current:").
    struct RestContext {
        let exercise: Exercise?
        /// True when rest leads into a different exercise (show full how-to).
        let isExerciseTransition: Bool
        /// Short label, e.g. "Next: Set 2 of 4" or "Up next".
        let label: String
        let instructions: String?
        let cues: [String]
    }

    var restContext: RestContext {
        let exercises = todayPlan?.orderedExercises ?? []
        if pendingRestAction == .nextExercise {
            let nextIndex = currentExerciseIndex + 1
            let next = nextIndex < exercises.count ? exercises[nextIndex] : nil
            let ex = next?.exercise
            return RestContext(
                exercise: ex,
                isExerciseTransition: true,
                label: ex.map { "Up next: \($0.name)" } ?? "Up next",
                instructions: ex?.instructions,
                cues: ex?.cues ?? []
            )
        } else {
            let ex = currentExercise?.exercise
            // Resting between sets — the next set is currentSetIndex + 1.
            let total = currentExercise?.orderedSets.count ?? 0
            let nextSetNumber = min(currentSetIndex + 2, total)
            return RestContext(
                exercise: ex,
                isExerciseTransition: false,
                label: ex.map { "\($0.name) · next: set \(nextSetNumber) of \(total)" } ?? "",
                instructions: nil,
                cues: []
            )
        }
    }

    var workoutTypeDisplayName: String {
        todayPlan?.type.displayName ?? "Rest"
    }

    var isRestDay: Bool {
        guard let plan = todayPlan else {
            return true
        }
        return plan.type == .rest || plan.type == .mobility
    }

    /// Whether today's plan is a loggable gym session — the ONLY case where a
    /// "Start Workout" button makes sense. Non-gym days (football, run, sprint,
    /// conditioning, mobility, rest) have no exercises to log, so the button is
    /// hidden for them. This is stricter than `!isRestDay`, which only excludes
    /// rest/mobility and wrongly left the button visible on football/run days.
    var canStartWorkout: Bool {
        guard let plan = todayPlan else {
            return false
        }
        return plan.type.isGymWorkout
    }

    var recoveryAdjustmentText: String? {
        guard let plan = todayPlan else {
            return nil
        }
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return nil
        }
        if adj >= 0.8 {
            return "Volume reduced 20% — Yellow recovery"
        }
        if adj >= 0.75 {
            return "Volume reduced 25%, lighter load — Yellow recovery"
        }
        return "Mobility session — Red recovery"
    }

    var stickyWeight: Double? {
        guard let exercise = currentExercise else {
            return nil
        }
        let sets = exercise.orderedSets
        // Return the last completed set's weight, or the target weight
        if currentSetIndex > 0 {
            let prevSet = sets[currentSetIndex - 1]
            return prevSet.actualWeight ?? prevSet.targetWeight
        }
        return sets.first?.targetWeight
    }

    // MARK: - Rest Timer

    // Per STATE_MACHINES.md Section 1 — Rest timer with haptic on completion

    private static let restTimerNotificationID = "tempo.rest.timer"

    private func startRestTimer(duration: TimeInterval, nextAction: RestNextAction) {
        stopRestTimer()
        restTimerTotal = duration
        restTimerRemaining = duration
        pendingRestAction = nextAction

        // Anchor to a wall-clock end instant. Every tick (and every foreground
        // re-sync) recomputes `restTimerRemaining` from this Date, so the timer
        // never freezes while the app is backgrounded.
        let end = Date().addingTimeInterval(duration)
        restEndDate = end
        // Arm the countdown cues: nothing has fired yet for this rest period.
        lastCuedSecond = Int(duration.rounded(.up)) + 1

        // Configure the audio session so voice/beep cues play (and duck music)
        // even when the screen is locked.
        Self.activateRestAudioSession()
        // Preload the countdown clips so playback at fire-time has no disk
        // latency (loading on the T-3 tick would reintroduce the lag we avoid).
        CueAudioPlayer.shared.preload([.tenSeconds, .three, .two, .one, .go])

        // Schedule a local notification so the user can lock their phone.
        scheduleRestTimerNotification(seconds: duration)

        restTimerTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(0.2))
                guard !Task.isCancelled, let self else {
                    return
                }
                if self.tickRestTimer() {
                    // Reached zero — tear the timer down BEFORE advancing so a
                    // foreground event during the next set can't see a stale
                    // restEndDate/restTimerTask and fire advanceAfterRest a
                    // second time (which would silently skip that set).
                    self.stopRestTimer()
                    self.advanceAfterRest()
                    return
                }
            }
        }
    }

    /// Recomputes `restTimerRemaining` from the wall-clock anchor and fires any
    /// countdown cues that were crossed since the last tick. Returns `true` when
    /// the rest period has elapsed (caller should advance).
    @discardableResult
    private func tickRestTimer() -> Bool {
        guard let end = restEndDate else {
            return false
        }
        let remaining = max(0, end.timeIntervalSinceNow)
        restTimerRemaining = remaining
        fireCuesIfNeeded(remaining: remaining)
        return remaining <= 0
    }

    /// Re-sync the rest timer after returning to the foreground. If the rest
    /// period already elapsed while backgrounded, advance immediately.
    func syncRestTimer() {
        guard restEndDate != nil, restTimerTask != nil else {
            return
        }
        if tickRestTimer() {
            stopRestTimer()
            advanceAfterRest()
        }
    }

    // MARK: - Guided Warm-Up Flow

    /// The move the user is currently on in the guided warm-up, if any.
    var currentWarmupMove: WarmupMove? {
        guard let moves = warmupRoutine?.moves, warmupMoveIndex < moves.count else {
            return nil
        }
        return moves[warmupMoveIndex]
    }

    /// Start (or arm) the timer for the current warm-up move. Timed moves run a
    /// Date-anchored countdown that auto-advances and survives backgrounding;
    /// rep-based moves run no timer (the user taps Next). Announces the move by
    /// voice so the user knows what to do without looking.
    func startWarmupMoveTimerForCurrent() {
        stopWarmupMoveTimer()
        guard let move = currentWarmupMove else {
            return
        }
        // Audio session is activated once in startWorkout for the whole warm-up.
        // The voice is intentionally SILENT on move announcements — Harry only
        // speaks the rest-timer countdown (T-10 warning + 3-2-1-go). Move names
        // are shown on screen, not spoken.

        guard let seconds = move.durationSeconds, seconds > 0 else {
            // Rep-based move — no countdown, advance is manual.
            warmupMoveRemaining = 0
            warmupMoveEndDate = nil
            return
        }
        warmupMoveRemaining = TimeInterval(seconds)
        let end = Date().addingTimeInterval(TimeInterval(seconds))
        warmupMoveEndDate = end
        warmupMoveTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(0.2))
                guard !Task.isCancelled, let self else {
                    return
                }
                if self.tickWarmupMove() {
                    // Tear down BEFORE advancing so a scenePhase resync can't
                    // double-advance the same move (mirrors the rest-timer fix).
                    self.stopWarmupMoveTimer()
                    self.advanceWarmupMove()
                    return
                }
            }
        }
    }

    @discardableResult
    private func tickWarmupMove() -> Bool {
        guard let end = warmupMoveEndDate else {
            return false
        }
        warmupMoveRemaining = max(0, end.timeIntervalSinceNow)
        return warmupMoveRemaining <= 0
    }

    /// Re-sync the warm-up move timer after returning to the foreground.
    /// A nil `warmupMoveTask` means the current move is rep-based (no timer was
    /// created), so there is nothing to re-sync — this no-op is correct, not a
    /// missed paused/crashed timer.
    func syncWarmupTimer() {
        guard warmupMoveEndDate != nil, warmupMoveTask != nil else {
            return
        }
        if tickWarmupMove() {
            stopWarmupMoveTimer()
            advanceWarmupMove()
        }
    }

    /// Advance to the next warm-up move, or into the working sets when the
    /// routine is finished. Idempotent: guarded on still being in .warmup.
    func advanceWarmupMove() {
        guard case .warmup = sessionState else {
            return
        }
        let moveCount = warmupRoutine?.moves.count ?? 0
        let next = warmupMoveIndex + 1
        if next < moveCount {
            warmupMoveIndex = next
            startWarmupMoveTimerForCurrent()
        } else {
            // Routine done — fall through to the ramp-set preview / working sets.
            stopWarmupMoveTimer()
            // Stay in .warmup so the ramp preview + "Start Working Sets" shows;
            // the view switches to the ramp preview once moves are exhausted.
            warmupMoveIndex = moveCount
        }
    }

    /// Skip the current warm-up move immediately.
    func skipWarmupMove() {
        stopWarmupMoveTimer()
        advanceWarmupMove()
    }

    private func stopWarmupMoveTimer() {
        warmupMoveTask?.cancel()
        warmupMoveTask = nil
        warmupMoveRemaining = 0
        warmupMoveEndDate = nil
    }

    // MARK: Rest Audio Cues
    //
    // Voice cues are played by CueAudioPlayer (premium pre-rendered clips for
    // the closed vocabulary; Apple-speech fallback for dynamic exercise names).
    // This VM owns only the audio-session activation and the system beep.

    /// Configure the shared audio session so cues are audible and DUCK (not stop)
    /// any music the user is playing, including when the screen is locked.
    private static func activateRestAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .duckOthers lowers (not stops) the user's music while a cue plays.
        // It is mutually exclusive with .mixWithOthers, so we use it alone.
        try? session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? session.setActive(true, options: [])
    }

    /// Release the audio session so the user's music returns to full volume.
    private static func deactivateRestAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func playBeep() {
        AudioServicesPlaySystemSound(1057)
    }

    /// Fire countdown cues exactly once as the remaining time crosses each
    /// threshold. Driven from the wall-clock tick, so cues still fire on the
    /// correct second after the app returns from the background.
    private func fireCuesIfNeeded(remaining: TimeInterval) {
        // Only consider whole-second thresholds we have not already cued.
        let current = Int(remaining.rounded(.up))
        guard current < lastCuedSecond else {
            return
        }
        defer { lastCuedSecond = current }

        let target = max(current, 0)
        // Normal 0.2s ticks cross one threshold at a time. If many thresholds
        // were crossed at once (the app was backgrounded), DON'T replay them as
        // a misleading "ten… three… two" burst — fire only the single most
        // urgent cue for where we actually are now.
        if lastCuedSecond - 1 - target > 1 {
            cue(for: target)
            return
        }
        for second in stride(from: lastCuedSecond - 1, through: target, by: -1) {
            cue(for: second)
        }
    }

    private func cue(for second: Int) {
        switch second {
        case 12:
            // "ten seconds" warning. A premium clip starts in ms, so fire it at
            // T-10; the Apple-speech fallback needs ~2s spin-up, so fire at T-12.
            if CueAudioPlayer.shared.hasClip(.tenSeconds) {
                break // handled at case 10 below for clip path
            }
            Self.playBeep()
            CueAudioPlayer.shared.play(.tenSeconds)
        case 10:
            // Clip path only (speech path already fired at 12).
            if CueAudioPlayer.shared.hasClip(.tenSeconds) {
                Self.playBeep()
                CueAudioPlayer.shared.play(.tenSeconds)
            }
        case 3:
            CueAudioPlayer.shared.play(.three)
        case 2:
            CueAudioPlayer.shared.play(.two)
        case 1:
            CueAudioPlayer.shared.play(.one)
        case 0:
            // Announce what's next by name. Exercise names are an OPEN set
            // (custom exercises), so they always use the Apple fallback via
            // .dynamic; the generic "go" has a premium clip.
            // Haptic at T-0 is owned by advanceAfterRest to avoid a double buzz.
            // Countdown only: always "Go" — the exercise name is shown on the
            // next screen, not spoken. (Voice scope is the countdown alone.)
            CueAudioPlayer.shared.play(.go)
        default:
            break
        }
    }

    private func stopRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
        restTimerRemaining = 0
        restEndDate = nil
        lastCuedSecond = Int.max
        cancelRestTimerNotification()
        Self.deactivateRestAudioSession()
    }

    /// Extends the current rest timer by the given number of seconds.
    

    // MARK: - Rest Timer Notifications

    /// IDs for the multi-cue rest notifications (T-10, T-3, T-2, T-1, T-0).
    private static let restCueNotificationIDs = [
        "tempo.rest.cue.10",
        "tempo.rest.cue.3",
        "tempo.rest.cue.2",
        "tempo.rest.cue.1",
        "tempo.rest.timer", // T-0 — keeps the original ID
    ]

    /// Schedule notification SOUNDS at each countdown beat so the cues are
    /// audible through earphones even with the phone LOCKED / in a pocket —
    /// the app's in-process AVSpeechSynthesizer cues only fire while the app is
    /// foregrounded (iOS suspends the timer Task on lock). These notifications
    /// are the locked-phone path; the in-app voice is the screen-on path.
    private func scheduleRestTimerNotification(seconds: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.restCueNotificationIDs)

        // (offsetFromEnd, id, title, body) — fire each at `seconds - offset`.
        let cues: [(Double, String, String, String)] = [
            (10, "tempo.rest.cue.10", "10 seconds", "Get ready — 10 seconds left."),
            (3, "tempo.rest.cue.3", "3", "Rest ending…"),
            (2, "tempo.rest.cue.2", "2", "Rest ending…"),
            (1, "tempo.rest.cue.1", "1", "Rest ending…"),
            (0, Self.restTimerNotificationID, "Rest Over", "Time to hit your next set."),
        ]

        for (offset, id, title, body) in cues {
            let fireAt = seconds - offset
            // Skip cues whose fire time is in the past (short rests have no T-10).
            guard fireAt >= 1 || offset == 0 else {
                continue
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, fireAt),
                repeats: false
            )
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { _ in }
        }
    }

    private func cancelRestTimerNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Self.restCueNotificationIDs)
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimerTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else {
                    return
                }
                if let start = workoutStartTime {
                    elapsedSeconds = Date().timeIntervalSince(start) - totalPauseDuration
                }
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
    }

    // MARK: - Private Helpers

    private func resetState() {
        currentExerciseIndex = 0
        currentSetIndex = 0
        workoutStartTime = nil
        elapsedSeconds = 0
        totalPauseDuration = 0
        detectedPRs = []
        warmupRoutine = nil
        warmupMoveIndex = 0
        stopRestTimer()
        stopWarmupMoveTimer()
        stopElapsedTimer()
    }

    private func restDuration(for exercise: PlannedExercise) -> TimeInterval {
        // Per MODULE_TRAINING.md Section 15.6 — Rest times by exercise type
        guard let ex = exercise.exercise else {
            return 90
        }

        // Check per-exercise custom rest time first
        if let preferred = ex.preferredRestSeconds {
            return TimeInterval(preferred)
        }

        if ex.isCompound {
            // Heavy compound: 150-180s, moderate compound: 120-150s
            switch ex.equipment {
            case .barbell: return 150
            case .dumbbell: return 120
            default: return 120
            }
        } else {
            // Isolation: 60-90s
            return 75
        }
    }

    // MARK: - Exercise Population

    // Populates a WorkoutPlan with exercises from the library based on workout type.

    func populateExercises(for plan: WorkoutPlan, modelContext: ModelContext) {
        guard plan.type.isGymWorkout else {
            return
        }
        guard plan.orderedExercises.isEmpty else {
            return
        } // already populated

        let targetGroups = muscleGroups(for: plan.type)
        guard !targetGroups.isEmpty else {
            return
        }

        // Fetch all exercises from library
        var descriptor = FetchDescriptor<Exercise>()
        descriptor.sortBy = [SortDescriptor(\Exercise.name)]
        guard let allExercises = try? modelContext.fetch(descriptor) else {
            return
        }

        // Select exercises: priority-ordered compounds first, then isolations
        let selected = selectExercises(
            from: allExercises,
            targetGroups: targetGroups,
            workoutType: plan.type
        )

        // Assign superset groups for compatible exercise pairs.
        // Pair compound + isolation targeting different muscle groups (e.g. bench + lateral raise).
        let supersetPairs = assignSupersetGroups(selected)

        // Build PlannedExercise + PlannedSet objects with target weights
        // Intelligent volume prescription:
        //   Primary compound (index 0): 4 working sets
        //   Secondary compounds (index 1-2): 3 working sets
        //   First isolation: 3 sets
        //   Remaining isolations: 2 sets
        // Target: 16-20 total working sets per session
        // Recovery-adjusted (yellow zone): reduce total volume by ~20%
        let isRecoveryReduced = plan.recoveryAdjustment < 1.0

        for (index, exercise) in selected.enumerated() {
            let baseNumSets: Int
            if exercise.isCompound {
                baseNumSets = (index == 0) ? 4 : 3
            } else {
                // First isolation gets 3, rest get 2
                let compoundCount = selected.prefix(index).filter(\.isCompound).count
                let isolationIndex = index - compoundCount
                baseNumSets = (isolationIndex == 0) ? 3 : 2
            }

            // Recovery-adjusted: drop 1 set from compounds, keep isolations as-is
            let numSets: Int = if isRecoveryReduced && exercise.isCompound {
                max(2, baseNumSets - 1)
            } else {
                baseNumSets
            }

            let reps = exercise.isCompound ? 8 : 12

            // Use progressive overload from history, or sensible defaults
            let history = exercise.history ?? []
            let overload = trainingEngine.calculateProgressiveOverload(for: exercise, history: history)
            let weight: Double = overload.weight > 0 ? overload.weight : defaultWeight(for: exercise)

            // Apply recovery adjustment and deload multiplier if applicable
            let deloadMultiplier = isDeloadWeek ? trainingEngine.deloadWeightMultiplier() : 1.0
            let adjustedWeight = weight * plan.recoveryAdjustment * deloadMultiplier
            let roundedWeight = (adjustedWeight / 2.5).rounded() * 2.5 // Round to nearest 2.5kg

            // Look up superset group assignment
            let supersetGroup = supersetPairs[exercise.id]

            let planned = PlannedExercise(
                order: index,
                supersetGroup: supersetGroup,
                workoutPlan: plan,
                exercise: exercise
            )

            var plannedSets: [PlannedSet] = []
            var setNum = 1

            // Add warmup sets for compound exercises (ramp up to working weight)
            if exercise.isCompound, roundedWeight > 0 {
                // Warmup set 1: 50% working weight, same reps
                let warmup1Weight = ((roundedWeight * 0.5) / 2.5).rounded() * 2.5
                let ws1 = PlannedSet(
                    setNumber: setNum,
                    targetReps: reps,
                    targetWeight: warmup1Weight,
                    isWarmup: true,
                    plannedExercise: planned
                )
                plannedSets.append(ws1)
                setNum += 1

                // Warmup set 2: 75% working weight, same reps
                let warmup2Weight = ((roundedWeight * 0.75) / 2.5).rounded() * 2.5
                let ws2 = PlannedSet(
                    setNumber: setNum,
                    targetReps: reps,
                    targetWeight: warmup2Weight,
                    isWarmup: true,
                    plannedExercise: planned
                )
                plannedSets.append(ws2)
                setNum += 1
            }

            // Working sets
            for _ in 1 ... numSets {
                let ps = PlannedSet(
                    setNumber: setNum,
                    targetReps: reps,
                    targetWeight: roundedWeight,
                    plannedExercise: planned
                )
                plannedSets.append(ps)
                setNum += 1
            }
            planned.sets = plannedSets
        }
    }

    /// Assigns superset group IDs to compatible exercise pairs.
    /// Pairs a compound exercise with an isolation exercise targeting a different muscle group.
    /// Returns a dictionary mapping exercise ID to superset group number.
    private func assignSupersetGroups(_ exercises: [Exercise]) -> [UUID: Int] {
        var assignments: [UUID: Int] = [:]
        var groupCounter = 1
        var paired = Set<UUID>()

        for (i, ex1) in exercises.enumerated() {
            guard !paired.contains(ex1.id) else {
                continue
            }
            guard ex1.isCompound else {
                continue
            }

            // Find the next isolation exercise targeting a different muscle group
            for j in (i + 1) ..< exercises.count {
                let ex2 = exercises[j]
                guard !paired.contains(ex2.id) else {
                    continue
                }
                guard !ex2.isCompound else {
                    continue
                }
                guard ex2.muscleGroup != ex1.muscleGroup else {
                    continue
                }

                // Pair found
                assignments[ex1.id] = groupCounter
                assignments[ex2.id] = groupCounter
                paired.insert(ex1.id)
                paired.insert(ex2.id)
                groupCounter += 1
                break
            }
        }

        return assignments
    }

    /// Maps workout type to the target muscle groups to train.
    private func muscleGroups(for type: WorkoutType) -> [MuscleGroup] {
        switch type {
        case .push: [.chest, .shoulders, .triceps]
        case .pull: [.back, .biceps]
        case .legs: [.quads, .hamstrings, .glutes, .calves]
        case .upper: [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: [.quads, .hamstrings, .glutes, .calves]
        case .fullBody: [.chest, .back, .shoulders, .quads, .hamstrings, .glutes]
        default: []
        }
    }

    /// Selects exercises from the library for a given workout type.
    /// Uses priority ordering per workout type and day-of-week seed for variation.
    /// Returns 5-6 exercises: compounds first, then isolations.
    private func selectExercises(
        from allExercises: [Exercise],
        targetGroups: [MuscleGroup],
        workoutType: WorkoutType
    ) -> [Exercise] {
        let matching = allExercises.filter { targetGroups.contains($0.muscleGroup) }
        let compounds = matching.filter(\.isCompound)
        let isolations = matching.filter { !$0.isCompound }

        // Priority ordering per workout type — ensures best exercise selection
        let priorityOrder = exercisePriorityOrder(for: workoutType)

        // Day-of-week seed for variation (so Monday Push != Thursday Push)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let variationSeed = dayOfYear

        var selected: [Exercise] = []
        var usedNames = Set<String>()

        // Phase 1: Pick compounds in priority order (2-3 compounds)
        let maxCompounds = 3
        for priorityName in priorityOrder where selected.count < maxCompounds {
            if let match = compounds.first(where: {
                $0.name == priorityName && !usedNames.contains($0.name)
            }) {
                selected.append(match)
                usedNames.insert(match.name)
            }
        }

        // Phase 2: Fill remaining compound slots from target groups if priority didn't cover them
        for group in targetGroups where selected.count < maxCompounds {
            let groupCompounds = compounds.filter {
                $0.muscleGroup == group && !usedNames.contains($0.name)
            }
            // Use variation seed to rotate through available compounds
            if !groupCompounds.isEmpty {
                let pick = groupCompounds[variationSeed % groupCompounds.count]
                selected.append(pick)
                usedNames.insert(pick.name)
            }
        }

        // Phase 3: Pick isolations in priority order (fill to 5-6 total)
        let targetTotal = 6
        for priorityName in priorityOrder where selected.count < targetTotal {
            if let match = isolations.first(where: {
                $0.name == priorityName && !usedNames.contains($0.name)
            }) {
                selected.append(match)
                usedNames.insert(match.name)
            }
        }

        // Phase 4: Fill remaining isolation slots from target groups with variation
        for group in targetGroups where selected.count < targetTotal {
            let groupIsolations = isolations.filter {
                $0.muscleGroup == group && !usedNames.contains($0.name)
            }
            if !groupIsolations.isEmpty {
                let pick = groupIsolations[variationSeed % groupIsolations.count]
                selected.append(pick)
                usedNames.insert(pick.name)
            }
        }

        // Phase 5: If still under 5, add any remaining isolations
        for iso in isolations where selected.count < 5 {
            if !usedNames.contains(iso.name) {
                selected.append(iso)
                usedNames.insert(iso.name)
            }
        }

        return selected
    }

    /// Priority exercise ordering per workout type.
    /// Compounds listed first, then isolations in recommended order.
    private func exercisePriorityOrder(for workoutType: WorkoutType) -> [String] {
        switch workoutType {
        case .push:
            [
                // Compounds
                "Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press",
                // Isolations
                "Lateral Raise", "Tricep Pushdown", "Skull Crusher",
                "Cable Fly", "Cable Lateral Raise", "Overhead Tricep Extension",
            ]
        case .pull:
            [
                // Compounds
                "Barbell Row", "Pull-Up", "Lat Pulldown",
                // Isolations
                "Face Pull", "Barbell Curl", "Hammer Curl",
                "Cable Curl", "Rear Delt Fly", "Straight-Arm Pulldown",
            ]
        case .legs:
            [
                // Compounds
                "Barbell Back Squat", "Leg Press", "Romanian Deadlift",
                // Isolations
                "Leg Curl", "Standing Calf Raise", "Leg Extension",
                "Seated Leg Curl", "Seated Calf Raise", "Bulgarian Split Squat",
            ]
        case .upper:
            [
                "Barbell Bench Press", "Barbell Row", "Overhead Press",
                "Lat Pulldown", "Lateral Raise", "Barbell Curl",
                "Tricep Pushdown",
            ]
        case .lower:
            [
                "Barbell Back Squat", "Romanian Deadlift", "Leg Press",
                "Leg Curl", "Standing Calf Raise", "Leg Extension",
                "Hip Thrust",
            ]
        case .fullBody:
            [
                "Barbell Back Squat", "Barbell Bench Press", "Barbell Row",
                "Overhead Press", "Romanian Deadlift", "Lateral Raise",
            ]
        default:
            []
        }
    }

    /// Sensible starting weights (kg) when no history exists.
    private func defaultWeight(for exercise: Exercise) -> Double {
        if exercise.isCompound {
            switch exercise.equipment {
            case .barbell: 40.0 // Empty bar + light plates
            case .dumbbell: 12.5 // Per hand
            case .cable: 25.0
            case .machine: 30.0
            default: 0 // Bodyweight
            }
        } else {
            switch exercise.equipment {
            case .barbell: 20.0
            case .dumbbell: 7.5
            case .cable: 15.0
            case .machine: 20.0
            default: 0 // Bodyweight
            }
        }
    }

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
