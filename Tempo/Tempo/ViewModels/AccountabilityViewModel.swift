import Foundation
import SwiftUI
import SwiftData

// MARK: - Focus Timer State
// Per STATE_MACHINES.md Section 2 — Focus Timer state machine.

enum FocusTimerState: Equatable, Sendable {
    case idle
    case configuring
    case focusing(remaining: TimeInterval)
    case sessionDone(sessionCount: Int)
    case onBreak(remaining: TimeInterval)
    case breakDone
    case longBreak(remaining: TimeInterval)
    case completed(totalSessions: Int)
    case review
    case paused(previous: PausedFocusState)
    case cancelled

    enum PausedFocusState: Equatable, Sendable {
        case focusing(remaining: TimeInterval)
        case onBreak(remaining: TimeInterval)
        case longBreak(remaining: TimeInterval)
    }

    var isActive: Bool {
        switch self {
        case .focusing, .onBreak, .longBreak: true
        default: false
        }
    }
}

// MARK: - Accountability ViewModel
// Per BUILD_PLAN step 10.2.
// Per MODULE_ACCOUNTABILITY.md — Accountability module state and logic.
// Per STATE_MACHINES.md Section 2 (Focus Timer) and Section 3 (Daily Accountability).

@Observable
@MainActor
final class AccountabilityViewModel {

    // MARK: - State

    var dailyState: DailyAccountabilityState = .morningSetup
    var accountability: DailyAccountability?
    var progressItems: [NonNegotiableProgress] = []
    var overallStreak: Streak?
    var isLoading = true
    var activeOverride: AccountabilityOverrideType?

    // MARK: - Focus Timer State
    // Per STATE_MACHINES.md Section 2

    var focusState: FocusTimerState = .idle
    var focusDuration: TimeInterval = 25 * 60 // Default 25 min pomodoro
    var breakDuration: TimeInterval = 5 * 60  // Default 5 min break
    var longBreakDuration: TimeInterval = 15 * 60
    var sessionsBeforeLongBreak = 4
    var currentSessionCount = 0
    var focusSubject: String?
    var currentStudySession: StudySession?

    // Timer internals
    private var focusTimerTask: Task<Void, Never>?
    private var focusStartDate: Date?
    var totalFocusMinutesToday: Int { accountability?.totalStudyMinutes ?? 0 }

    // MARK: - Computed

    var isLeisureUnlocked: Bool { accountability?.leisureUnlocked ?? false }

    var completionPercentage: Double { accountability?.completionPercentage ?? 0 }

    var completedCount: Int { accountability?.completedCount ?? 0 }

    var totalCount: Int { accountability?.totalCount ?? 0 }

    var streakCount: Int { overallStreak?.currentCount ?? 0 }

    var longestStreak: Int { overallStreak?.longestCount ?? 0 }

    var isStreakAtRisk: Bool {
        guard let accountability, let streak = overallStreak else { return false }
        return engine.isStreakAtRisk(accountability: accountability, streak: streak)
    }

    var ps5TimeToday: Date { engine.ps5Time() }

    var formattedPS5Time: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: ps5TimeToday)
    }

    var timeToPS5: TimeInterval {
        max(0, ps5TimeToday.timeIntervalSince(Date()))
    }

    var formattedTimeToPS5: String {
        let hours = Int(timeToPS5) / 3600
        let minutes = (Int(timeToPS5) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var formattedFocusTimer: String {
        let remaining: TimeInterval
        switch focusState {
        case .focusing(let r), .onBreak(let r), .longBreak(let r):
            remaining = r
        case .paused(let prev):
            switch prev {
            case .focusing(let r), .onBreak(let r), .longBreak(let r):
                remaining = r
            }
        default:
            remaining = 0
        }
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var focusTimerProgress: Double {
        let total: TimeInterval
        let remaining: TimeInterval

        switch focusState {
        case .focusing(let r):
            total = focusDuration
            remaining = r
        case .onBreak(let r):
            total = breakDuration
            remaining = r
        case .longBreak(let r):
            total = longBreakDuration
            remaining = r
        default:
            return 0
        }
        guard total > 0 else { return 0 }
        return 1 - (remaining / total)
    }

    // MARK: - Dependencies

    private let engine: AccountabilityEngine

    // MARK: - Init

    init(engine: AccountabilityEngine = AccountabilityEngine()) {
        self.engine = engine
    }

    // MARK: - Load Today

    func loadToday(modelContext: ModelContext) {
        isLoading = true

        accountability = engine.loadTodayNonNegotiables(modelContext: modelContext)
        progressItems = accountability?.nonNegotiableProgress ?? []
        loadStreak(modelContext: modelContext)
        refreshState()

        isLoading = false
    }

    private func loadStreak(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Streak>(
            predicate: #Predicate { s in s.typeRaw == "overall" }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            overallStreak = existing
        } else {
            let streak = Streak(type: .overall)
            modelContext.insert(streak)
            try? modelContext.save()
            overallStreak = streak
        }
    }

    // MARK: - State Refresh

    func refreshState() {
        guard let accountability else { return }
        dailyState = engine.evaluateState(
            accountability: accountability,
            override: activeOverride,
            ps5Time: ps5TimeToday
        )
    }

    // MARK: - Manual Check-Off
    // Per MODULE_ACCOUNTABILITY.md — manual completion flow.

    func completeItem(
        _ progress: NonNegotiableProgress,
        modelContext: ModelContext
    ) {
        engine.updateProgress(
            progress: progress,
            newValue: progress.targetValue,
            modelContext: modelContext
        )

        refreshProgressItems()
        checkForUnlock(modelContext: modelContext)
    }

    func updateItemProgress(
        _ progress: NonNegotiableProgress,
        value: Double,
        modelContext: ModelContext
    ) {
        engine.updateProgress(
            progress: progress,
            newValue: value,
            modelContext: modelContext
        )

        refreshProgressItems()
        checkForUnlock(modelContext: modelContext)
    }

    func skipItem(
        _ progress: NonNegotiableProgress,
        modelContext: ModelContext
    ) {
        engine.skipNonNegotiable(progress: progress, modelContext: modelContext)

        refreshProgressItems()
        checkForUnlock(modelContext: modelContext)
    }

    private func refreshProgressItems() {
        progressItems = accountability?.nonNegotiableProgress ?? []
        refreshState()
    }

    private func checkForUnlock(modelContext: ModelContext) {
        guard let accountability else { return }
        let newlyUnlocked = engine.processUnlock(
            accountability: accountability,
            modelContext: modelContext
        )

        if newlyUnlocked {
            // Per acceptance criteria: leisure unlock triggers haptic + sound
            HapticManager.notification(.success)
            HapticManager.notification(.success)
            HapticManager.notification(.success)
            refreshState()
        }
    }

    // MARK: - Override Actions
    // Per MODULE_ACCOUNTABILITY.md Section 13

    func activateOverride(
        type: AccountabilityOverrideType,
        modelContext: ModelContext
    ) {
        guard let accountability else { return }
        activeOverride = type
        engine.applyRestDayOverride(
            accountability: accountability,
            type: type,
            modelContext: modelContext
        )
        refreshProgressItems()
    }

    func deactivateOverride() {
        activeOverride = nil
        refreshState()
    }

    // MARK: - Focus Timer
    // Per STATE_MACHINES.md Section 2 — Focus Timer state machine.

    func configureFocusTimer(duration: TimeInterval = 25 * 60, subject: String? = nil) {
        focusDuration = duration
        focusSubject = subject
        focusState = .configuring
    }

    func startFocusSession(modelContext: ModelContext) {
        guard let accountability else { return }

        // Create study session
        let session = StudySession(
            startTime: Date(),
            subject: focusSubject,
            sessionType: .pomodoro,
            dailyAccountability: accountability
        )
        modelContext.insert(session)
        currentStudySession = session
        focusStartDate = Date()

        // Start timer
        // Per STATE_MACHINES.md Section 2: configuring/breakDone → focusing
        focusState = .focusing(remaining: focusDuration)
        startFocusCountdown(total: focusDuration, modelContext: modelContext)
    }

    func pauseFocus() {
        guard case let currentState = focusState, currentState.isActive else { return }
        focusTimerTask?.cancel()

        switch focusState {
        case .focusing(let r):
            focusState = .paused(previous: .focusing(remaining: r))
        case .onBreak(let r):
            focusState = .paused(previous: .onBreak(remaining: r))
        case .longBreak(let r):
            focusState = .paused(previous: .longBreak(remaining: r))
        default:
            break
        }
    }

    func resumeFocus(modelContext: ModelContext) {
        guard case .paused(let previous) = focusState else { return }

        switch previous {
        case .focusing(let r):
            focusState = .focusing(remaining: r)
            startFocusCountdown(total: r, modelContext: modelContext)
        case .onBreak(let r):
            focusState = .onBreak(remaining: r)
            startBreakCountdown(total: r)
        case .longBreak(let r):
            focusState = .longBreak(remaining: r)
            startBreakCountdown(total: r)
        }
    }

    func cancelFocus(modelContext: ModelContext) {
        focusTimerTask?.cancel()

        // Save partial if > 5 min
        // Per STATE_MACHINES.md Section 2: Any active → cancelled (save partial if > 5 min)
        if let session = currentStudySession, let start = focusStartDate {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 5 * 60 {
                session.endTime = Date()
                session.durationMinutes = Int(elapsed / 60)
                try? modelContext.save()
            } else {
                modelContext.delete(session)
                try? modelContext.save()
            }
        }

        currentStudySession = nil
        focusStartDate = nil
        focusState = .cancelled
        // Return to idle after brief delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            focusState = .idle
        }
    }

    func startBreak() {
        let isLong = (currentSessionCount % sessionsBeforeLongBreak == 0) && currentSessionCount > 0
        let duration = isLong ? longBreakDuration : breakDuration

        if isLong {
            focusState = .longBreak(remaining: duration)
        } else {
            focusState = .onBreak(remaining: duration)
        }
        startBreakCountdown(total: duration)
    }

    func skipBreak(modelContext: ModelContext) {
        focusTimerTask?.cancel()
        startNextSession(modelContext: modelContext)
    }

    func finishFocusReview(modelContext: ModelContext) {
        // Per STATE_MACHINES.md Section 2: review → idle (save session to SwiftData)
        if let session = currentStudySession, let start = focusStartDate {
            session.endTime = Date()
            session.durationMinutes = Int(Date().timeIntervalSince(start) / 60)
            session.completedPomodoros = currentSessionCount

            // Update daily study minutes
            accountability?.totalStudyMinutes += session.durationMinutes

            // Update study non-negotiable progress
            updateStudyProgress(minutes: session.durationMinutes, modelContext: modelContext)

            try? modelContext.save()
        }

        currentStudySession = nil
        focusStartDate = nil
        currentSessionCount = 0
        focusState = .idle
    }

    // MARK: - Focus Timer Internals

    private func startFocusCountdown(total: TimeInterval, modelContext: ModelContext) {
        focusTimerTask?.cancel()
        focusTimerTask = Task { [weak self] in
            var remaining = total
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                await MainActor.run {
                    self?.focusState = .focusing(remaining: remaining)
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.currentSessionCount += 1
                HapticManager.notification(.success)
                let allDone = (self?.currentSessionCount ?? 0) >= (self?.sessionsBeforeLongBreak ?? 4)
                if allDone {
                    self?.focusState = .completed(totalSessions: self?.currentSessionCount ?? 0)
                } else {
                    self?.focusState = .sessionDone(sessionCount: self?.currentSessionCount ?? 0)
                }
            }
        }
    }

    private func startBreakCountdown(total: TimeInterval) {
        focusTimerTask?.cancel()
        focusTimerTask = Task { [weak self] in
            var remaining = total
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                let isLong = total > 10 * 60
                await MainActor.run {
                    if isLong {
                        self?.focusState = .longBreak(remaining: remaining)
                    } else {
                        self?.focusState = .onBreak(remaining: remaining)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                HapticManager.impact(.light)
                self?.focusState = .breakDone
            }
        }
    }

    private func startNextSession(modelContext: ModelContext) {
        focusState = .focusing(remaining: focusDuration)
        startFocusCountdown(total: focusDuration, modelContext: modelContext)
    }

    private func updateStudyProgress(minutes: Int, modelContext: ModelContext) {
        guard let studyProgress = progressItems.first(where: {
            $0.nonNegotiable?.type == .study
        }) else { return }

        let newValue = studyProgress.currentValue + Double(minutes)
        engine.updateProgress(progress: studyProgress, newValue: newValue, modelContext: modelContext)
        refreshProgressItems()
        checkForUnlock(modelContext: modelContext)
    }

    // MARK: - End of Day

    func processEndOfDay(modelContext: ModelContext) {
        guard let accountability, let streak = overallStreak else { return }

        // Update score
        accountability.accountabilityScore = engine.calculateDailyScore(accountability: accountability)

        // Update streak
        engine.updateStreak(
            streak: streak,
            dayCompleted: accountability.allComplete,
            override: activeOverride,
            modelContext: modelContext
        )

        // Check milestone
        if let milestone = engine.streakMilestone(count: streak.currentCount) {
            HapticManager.notification(.success)
            // Milestone handling (badges, XP) will be connected in Phase 14
            _ = milestone
        }

        try? modelContext.save()
        dailyState = .review
    }
}
