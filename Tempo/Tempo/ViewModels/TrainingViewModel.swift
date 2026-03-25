import Foundation
import SwiftUI
import SwiftData

// MARK: - Workout Session State
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
        case .warmup, .exercise, .cooldown: true
        default: false
        }
    }
}

// MARK: - Training ViewModel
// Per MODULE_TRAINING.md Sections 2, 9, 15 and BUILD_PLAN.md Step 9.2.
// Per STATE_MACHINES.md Section 1 — Workout Session state machine.

@Observable
@MainActor
final class TrainingViewModel {

    // MARK: - State

    var sessionState: WorkoutSessionState = .idle
    var todayPlan: WorkoutPlan?
    var weekPlans: [WorkoutPlan] = []
    var isLoading = true

    // MARK: - Active Workout State

    var currentExerciseIndex: Int = 0
    var currentSetIndex: Int = 0
    var workoutStartTime: Date?
    var elapsedSeconds: TimeInterval = 0
    var totalPauseDuration: TimeInterval = 0
    var detectedPRs: [PersonalRecord] = []

    // MARK: - Rest Timer

    var restTimerRemaining: TimeInterval = 0
    var restTimerTotal: TimeInterval = 0
    private var restTimerTask: Task<Void, Never>?

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

        // Check for existing plan in SwiftData
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.date == today }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            todayPlan = existing

            // Check for crash recovery
            if existing.status == .inProgress {
                sessionState = .crashedRecovery
            }
        } else {
            // Generate new plan
            let footballDays = loadFootballDays(modelContext: modelContext)
            let split = loadTrainingSplit(modelContext: modelContext)
            let recoveryScore = loadRecoveryScore(modelContext: modelContext)

            let plan = trainingEngine.generateWorkout(
                for: Date(),
                recoveryScore: recoveryScore,
                footballDays: footballDays,
                split: split
            )

            modelContext.insert(plan)
            try? modelContext.save()
            todayPlan = plan
        }

        isLoading = false
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
        let recoveryScore = loadRecoveryScore(modelContext: modelContext)

        weekPlans = trainingEngine.generateWeekPlan(
            startDate: monday,
            recoveryScore: recoveryScore,
            footballDays: footballDays,
            split: split
        )
    }

    // MARK: - Start Workout
    // Per STATE_MACHINES.md Section 1 — idle → warmup/exercise

    func startWorkout() {
        guard sessionState == .idle || sessionState == .crashedRecovery else { return }
        guard let plan = todayPlan else { return }

        plan.status = .inProgress
        plan.startedAt = Date()
        workoutStartTime = Date()
        elapsedSeconds = 0
        totalPauseDuration = 0
        currentExerciseIndex = 0
        currentSetIndex = 0
        detectedPRs = []

        // Transition to first exercise
        sessionState = .exercise(.setActive(exerciseIndex: 0, setIndex: 0))
        startElapsedTimer()
    }

    // MARK: - Resume from Crash Recovery

    func resumeFromCrash() {
        guard sessionState == .crashedRecovery, let plan = todayPlan else { return }

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
        guard sessionState == .crashedRecovery else { return }
        if let plan = todayPlan {
            plan.status = .skipped
        }
        try? modelContext.save()
        sessionState = .discarded
        resetState()
    }

    // MARK: - Log Set
    // Per STATE_MACHINES.md — exercise.setActive → exercise.resting

    func logSet(
        weight: Double,
        reps: Int,
        rpe: Int?,
        modelContext: ModelContext
    ) {
        guard let plan = todayPlan else { return }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else { return }

        let plannedExercise = exercises[currentExerciseIndex]
        let sets = plannedExercise.orderedSets

        guard currentSetIndex < sets.count else { return }

        let set = sets[currentSetIndex]
        set.actualWeight = weight
        set.actualReps = reps
        set.rpe = rpe
        set.completed = true
        set.completedAt = Date()

        // Persist immediately (crash recovery)
        try? modelContext.save()

        // PR detection
        if let exercise = plannedExercise.exercise {
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

        if isLastSet && isLastExercise {
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
        guard let plan = todayPlan else { return }
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

    func saveWorkout(modelContext: ModelContext) async {
        guard let plan = todayPlan else { return }

        plan.status = .completed
        plan.finishedAt = Date()
        plan.durationMinutes = Int(elapsedSeconds / 60)

        // Persist to SwiftData
        try? modelContext.save()

        // Write to HealthKit (via step 5.7)
        // The HealthKit write is best-effort; don't block on failure
        // (Full HealthKit workout writing is implemented in Phase 5)

        sessionState = .saved
        resetState()
    }

    // MARK: - Pause / Resume
    // Per STATE_MACHINES.md — any active → paused

    func pause() {
        guard sessionState.isActive else { return }

        let previousState: WorkoutSessionState.PausedFromState
        switch sessionState {
        case .warmup(let ei, let si):
            previousState = .warmup(exerciseIndex: ei, warmupSetIndex: si)
        case .exercise(let sub):
            previousState = .exercise(sub)
        case .cooldown:
            previousState = .cooldown
        default:
            return
        }

        stopRestTimer()
        stopElapsedTimer()
        sessionState = .paused(previousState: previousState, pauseStartTime: Date())
    }

    func resume() {
        guard case .paused(let previousState, let pauseStart) = sessionState else { return }

        // Track pause duration
        totalPauseDuration += Date().timeIntervalSince(pauseStart)

        // Restore previous state
        switch previousState {
        case .warmup(let ei, let si):
            sessionState = .warmup(exerciseIndex: ei, warmupSetIndex: si)
        case .exercise(let sub):
            sessionState = .exercise(sub)
        case .cooldown:
            sessionState = .cooldown
        }

        startElapsedTimer()
    }

    // MARK: - Computed Properties
    // Per MODULE_TRAINING.md Section 2 — Display values

    var currentExercise: PlannedExercise? {
        guard let plan = todayPlan else { return nil }
        let exercises = plan.orderedExercises
        guard currentExerciseIndex < exercises.count else { return nil }
        return exercises[currentExerciseIndex]
    }

    var currentSet: PlannedSet? {
        guard let exercise = currentExercise else { return nil }
        let sets = exercise.orderedSets
        guard currentSetIndex < sets.count else { return nil }
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
        let vol = totalVolume
        if vol >= 1000 {
            return String(format: "%.1fk kg", vol / 1000)
        }
        return "\(Int(vol)) kg"
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
        guard restTimerTotal > 0 else { return 0 }
        return 1.0 - (restTimerRemaining / restTimerTotal)
    }

    var setCountText: String {
        guard let exercise = currentExercise else { return "" }
        let total = exercise.orderedSets.count
        return "Set \(currentSetIndex + 1) of \(total)"
    }

    var workoutTypeDisplayName: String {
        todayPlan?.type.displayName ?? "Rest"
    }

    var isRestDay: Bool {
        guard let plan = todayPlan else { return true }
        return plan.type == .rest || plan.type == .mobility
    }

    var recoveryAdjustmentText: String? {
        guard let plan = todayPlan else { return nil }
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 { return nil }
        if adj >= 0.8 { return "Volume reduced 20% — Yellow recovery" }
        if adj >= 0.75 { return "Volume reduced 25%, lighter load — Yellow recovery" }
        return "Mobility session — Red recovery"
    }

    var stickyWeight: Double? {
        guard let exercise = currentExercise else { return nil }
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

    private func startRestTimer(duration: TimeInterval, nextAction: RestNextAction) {
        stopRestTimer()
        restTimerTotal = duration
        restTimerRemaining = duration
        pendingRestAction = nextAction

        restTimerTask = Task { @MainActor [weak self] in
            while let self, self.restTimerRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.restTimerRemaining = max(0, self.restTimerRemaining - 1)
            }
            guard !Task.isCancelled else { return }
            // Timer complete
            HapticManager.notification(.warning)
            self?.advanceAfterRest()
        }
    }

    private func stopRestTimer() {
        restTimerTask?.cancel()
        restTimerTask = nil
        restTimerRemaining = 0
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimerTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if let start = self.workoutStartTime {
                    self.elapsedSeconds = Date().timeIntervalSince(start) - self.totalPauseDuration
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
        stopRestTimer()
        stopElapsedTimer()
    }

    private func restDuration(for exercise: PlannedExercise) -> TimeInterval {
        // Per MODULE_TRAINING.md Section 15.6 — Rest times by exercise type
        guard let ex = exercise.exercise else { return 90 }

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

    private func loadRecoveryScore(modelContext: ModelContext) -> Double? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date == today },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first?.recoveryScore
    }
}
