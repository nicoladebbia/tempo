//
// AccountabilityViewModel.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - FocusTimerState

// Per STATE_MACHINES.md Section 2 — Focus Timer state machine.

enum FocusTimerState: Equatable {
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

    enum PausedFocusState: Equatable {
        case focusing(remaining: TimeInterval)
        case onBreak(remaining: TimeInterval)
        case longBreak(remaining: TimeInterval)
    }

    var isActive: Bool {
        switch self {
        case .focusing,
             .onBreak,
             .longBreak: true
        default: false
        }
    }
}

// MARK: - AccountabilityViewModel

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
    var breakDuration: TimeInterval = 5 * 60 // Default 5 min break
    var longBreakDuration: TimeInterval = 15 * 60
    var sessionsBeforeLongBreak = 4
    var currentSessionCount = 0
    var focusSubject: String?
    var currentStudySession: StudySession?

    // Timer internals
    private var focusTimerTask: Task<Void, Never>?
    private var focusStartDate: Date?
    var totalFocusMinutesToday: Int {
        accountability?.totalStudyMinutes ?? 0
    }

    // MARK: - Computed

    var isLeisureUnlocked: Bool {
        accountability?.leisureUnlocked ?? false
    }

    var completionPercentage: Double {
        accountability?.completionPercentage ?? 0
    }

    var completedCount: Int {
        accountability?.completedCount ?? 0
    }

    var totalCount: Int {
        accountability?.totalCount ?? 0
    }

    var streakCount: Int {
        overallStreak?.currentCount ?? 0
    }

    var longestStreak: Int {
        overallStreak?.longestCount ?? 0
    }

    var isStreakAtRisk: Bool {
        guard let accountability, let streak = overallStreak else {
            return false
        }
        return engine.isStreakAtRisk(accountability: accountability, streak: streak)
    }

    var ps5TimeToday: Date {
        engine.ps5Time()
    }

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
        let remaining: TimeInterval = switch focusState {
        case let .focusing(r),
             let .onBreak(r),
             let .longBreak(r):
            r
        case let .paused(prev):
            switch prev {
            case let .focusing(r),
                 let .onBreak(r),
                 let .longBreak(r):
                r
            }
        default:
            0
        }
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var focusTimerProgress: Double {
        let total: TimeInterval
        let remaining: TimeInterval

        switch focusState {
        case let .focusing(r):
            total = focusDuration
            remaining = r
        case let .onBreak(r):
            total = breakDuration
            remaining = r
        case let .longBreak(r):
            total = longBreakDuration
            remaining = r
        default:
            return 0
        }
        guard total > 0 else {
            return 0
        }
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
        loadHabitStreaks(modelContext: modelContext)
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
        guard let accountability else {
            return
        }
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

        // Update per-habit streak when a non-negotiable is completed
        if let nnType = progress.nonNegotiable?.type {
            updateHabitStreak(for: nnType, completed: true, modelContext: modelContext)
        }

        refreshProgressItems()
        checkForUnlock(modelContext: modelContext)
        NotificationCenter.default.post(name: .tempoNonNegotiableChanged, object: nil)
    }

    func updateItemProgress(
        _ progress: NonNegotiableProgress,
        value: Double,
        modelContext: ModelContext
    ) {
        let wasCompleted = progress.isCompleted

        engine.updateProgress(
            progress: progress,
            newValue: value,
            modelContext: modelContext
        )

        // Update per-habit streak when progress crosses completion threshold
        if !wasCompleted, progress.isCompleted, let nnType = progress.nonNegotiable?.type {
            updateHabitStreak(for: nnType, completed: true, modelContext: modelContext)
        }

        refreshProgressItems()
        checkForUnlock(modelContext: modelContext)
        NotificationCenter.default.post(name: .tempoNonNegotiableChanged, object: nil)
    }

    func skipItem(
        _ progress: NonNegotiableProgress,
        modelContext: ModelContext
    ) {
        engine.skipNonNegotiable(progress: progress, modelContext: modelContext)

        refreshProgressItems()
        checkForUnlock(modelContext: modelContext)
        NotificationCenter.default.post(name: .tempoNonNegotiableChanged, object: nil)
    }

    private func refreshProgressItems() {
        progressItems = accountability?.nonNegotiableProgress ?? []
        refreshState()
    }

    private func checkForUnlock(modelContext: ModelContext) {
        guard let accountability else {
            return
        }
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
        guard let accountability else {
            return
        }
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
        guard let accountability else {
            return
        }

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
        // Per spec B49 — clear focus-score inputs at session start.
        distractionCount = 0
        pauseCount = 0
        totalPauseDuration = 0
        pauseStartedAt = nil

        // Per spec B37–B40 — start Live Activity for lock screen + Dynamic Island.
        FocusTimerActivityManager.shared.start(
            sessionID: session.id.uuidString,
            phaseEndsAt: Date().addingTimeInterval(focusDuration),
            phaseLabel: "FOCUS TIME",
            progress: 0,
            subject: focusSubject,
            sessionIndex: currentSessionCount + 1,
            totalSessions: sessionsBeforeLongBreak
        )

        // Start timer
        // Per STATE_MACHINES.md Section 2: configuring/breakDone → focusing
        focusState = .focusing(remaining: focusDuration)
        startFocusCountdown(total: focusDuration, modelContext: modelContext)
    }

    func pauseFocus() {
        guard case let currentState = focusState, currentState.isActive else {
            return
        }
        focusTimerTask?.cancel()

        // Per spec B49 — track pause frequency and duration for the Focus Score.
        if case .focusing = focusState {
            pauseCount += 1
            pauseStartedAt = Date()
        }

        switch focusState {
        case let .focusing(r):
            focusState = .paused(previous: .focusing(remaining: r))
        case let .onBreak(r):
            focusState = .paused(previous: .onBreak(remaining: r))
        case let .longBreak(r):
            focusState = .paused(previous: .longBreak(remaining: r))
        default:
            break
        }
    }

    func resumeFocus(modelContext: ModelContext) {
        guard case let .paused(previous) = focusState else {
            return
        }

        // Accumulate the elapsed pause duration before clearing the marker.
        if let startedAt = pauseStartedAt {
            totalPauseDuration += Date().timeIntervalSince(startedAt)
            pauseStartedAt = nil
        }

        switch previous {
        case let .focusing(r):
            focusState = .focusing(remaining: r)
            startFocusCountdown(total: r, modelContext: modelContext)
        case let .onBreak(r):
            focusState = .onBreak(remaining: r)
            startBreakCountdown(total: r)
        case let .longBreak(r):
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
                session.distractions = distractionCount
                try? modelContext.save()
            } else {
                modelContext.delete(session)
                try? modelContext.save()
            }
        }

        currentStudySession = nil
        focusStartDate = nil
        distractionCount = 0
        pauseCount = 0
        totalPauseDuration = 0
        pauseStartedAt = nil
        FocusTimerActivityManager.shared.endCurrentDetached()
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
        if let session = currentStudySession {
            session.endTime = Date()
            session.distractions = distractionCount
            session.focusScore = computeFocusScore(for: session)

            // Note: study minutes and progress are saved incrementally
            // after each pomodoro in savePartialSession(). We only finalize
            // the end time and focus score here to avoid double-counting.

            try? modelContext.save()
        }

        currentStudySession = nil
        focusStartDate = nil
        currentSessionCount = 0
        distractionCount = 0
        pauseCount = 0
        totalPauseDuration = 0
        pauseStartedAt = nil
        FocusTimerActivityManager.shared.endCurrentDetached()
        focusState = .idle
    }

    // MARK: - Focus Score (spec B49)

    /// Composite 0–100 focus quality score per MODULE_ACCOUNTABILITY.md §3.13:
    /// 35% distraction + 25% pause-frequency + 20% pause-duration + 20% completion.
    func computeFocusScore(for session: StudySession) -> Int {
        // Distractions: 0=100, 1-2=85, 3-4=65, 5+=40
        let distractionScore: Double = switch distractionCount {
        case 0: 100
        case 1 ... 2: 85
        case 3 ... 4: 65
        default: 40
        }

        // Pause frequency normalized to 25-min blocks of focus.
        let elapsedMinutes = max(1.0, Double(session.durationMinutes))
        let blocks = max(1.0, elapsedMinutes / 25.0)
        let pausesPerBlock = Double(pauseCount) / blocks
        let pauseFreqScore: Double = switch pausesPerBlock {
        case ..<0.5: 100
        case ..<1.5: 90
        case ..<2.5: 70
        default: 50
        }

        // Pause duration ratio: pause time vs total focus time.
        let totalFocusSeconds = max(60.0, elapsedMinutes * 60.0)
        let pauseRatio = totalPauseDuration / totalFocusSeconds
        let pauseDurationScore: Double = switch pauseRatio {
        case ..<0.05: 100
        case ..<0.15: 80
        case ..<0.30: 55
        default: 30
        }

        // Completion: ratio of completed pomodoros to planned (sessionsBeforeLongBreak).
        let planned = max(1, sessionsBeforeLongBreak)
        let completionRatio = Double(currentSessionCount) / Double(planned)
        let completionScore: Double = switch completionRatio {
        case 1.0...: 100
        case 0.75 ..< 1.0: 80
        case 0.5 ..< 0.75: 50
        default: 20
        }

        let composite = (distractionScore * 0.35)
            + (pauseFreqScore * 0.25)
            + (pauseDurationScore * 0.20)
            + (completionScore * 0.20)
        return Int(min(100, max(0, composite)))
    }

    // MARK: - Per-Habit Streaks

    var habitStreaks: [NonNegotiableType: Streak] = [:]

    func loadHabitStreaks(modelContext: ModelContext) {
        let streakTypes: [(NonNegotiableType, StreakType)] = [
            (.study, .study),
            (.train, .training),
            (.meals, .meals),
        ]

        for (nnType, streakType) in streakTypes {
            let raw = streakType.rawValue
            let descriptor = FetchDescriptor<Streak>(
                predicate: #Predicate { s in s.typeRaw == raw }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                habitStreaks[nnType] = existing
            } else {
                let streak = Streak(type: streakType)
                modelContext.insert(streak)
                habitStreaks[nnType] = streak
            }
        }
        try? modelContext.save()
    }

    func updateHabitStreak(
        for nnType: NonNegotiableType,
        completed: Bool,
        modelContext: ModelContext
    ) {
        guard let streak = habitStreaks[nnType] else {
            return
        }
        if completed {
            streak.recordCompletion()
        }
        try? modelContext.save()
    }

    func habitStreakCount(for nnType: NonNegotiableType) -> Int {
        habitStreaks[nnType]?.currentCount ?? 0
    }

    // MARK: - Focus Timer Distraction Count (persisted across view dismiss)

    var distractionCount: Int = 0

    // MARK: - Focus Timer Pause Tracking (per spec B49)

    /// Number of times the user paused the timer during the current session.
    var pauseCount: Int = 0

    /// Cumulative seconds spent in paused state during the current session.
    var totalPauseDuration: TimeInterval = 0

    /// Timestamp when the most recent pause began. Cleared on resume.
    private var pauseStartedAt: Date?

    // MARK: - Save Partial Focus Session

    /// Save session progress incrementally after each completed pomodoro
    /// so that data survives an app kill mid-session.
    private func savePartialSession(modelContext: ModelContext) {
        guard let session = currentStudySession, let start = focusStartDate else {
            return
        }
        session.endTime = Date()
        session.durationMinutes = Int(Date().timeIntervalSince(start) / 60)
        session.completedPomodoros = currentSessionCount
        session.distractions = distractionCount

        // Update daily study minutes incrementally
        let pomodoroMinutes = Int(focusDuration / 60)
        accountability?.totalStudyMinutes += pomodoroMinutes
        updateStudyProgress(minutes: pomodoroMinutes, modelContext: modelContext)

        try? modelContext.save()
    }

    // MARK: - Focus Timer Internals

    private func startFocusCountdown(total: TimeInterval, modelContext: ModelContext) {
        focusTimerTask?.cancel()
        focusTimerTask = Task { [weak self] in
            var remaining = total
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                remaining -= 1
                await MainActor.run {
                    self?.focusState = .focusing(remaining: remaining)
                }
            }
            guard !Task.isCancelled else {
                return
            }
            await MainActor.run {
                self?.currentSessionCount += 1
                HapticManager.notification(.success)

                // Save partial session after each completed pomodoro
                // so progress is preserved if the app is killed.
                self?.savePartialSession(modelContext: modelContext)

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
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
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
            guard !Task.isCancelled else {
                return
            }
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
        })
        else {
            return
        }

        let newValue = studyProgress.currentValue + Double(minutes)
        engine.updateProgress(progress: studyProgress, newValue: newValue, modelContext: modelContext)
        refreshProgressItems()
        checkForUnlock(modelContext: modelContext)
    }

    // MARK: - Smart Notification Scheduling

    // Schedules context-aware notifications based on historical completion patterns.
    // Progressive urgency: gentle at 50% time remaining, firm at 25%, urgent at 10%.

    func scheduleSmartNotifications(
        notificationService: NotificationService,
        modelContext: ModelContext
    ) {
        guard let accountability, !accountability.leisureUnlocked else {
            return
        }
        guard activeOverride == nil else {
            return
        }

        let now = Date()
        let ps5Time = ps5TimeToday
        let timeToPS5 = ps5Time.timeIntervalSince(now)
        guard timeToPS5 > 0 else {
            return
        }

        let completedCount = accountability.completedCount
        let totalCount = accountability.totalCount
        guard totalCount > 0, completedCount < totalCount else {
            return
        }

        let remaining = totalCount - completedCount
        let streakDays = overallStreak?.currentCount ?? 0

        // Calculate historical study start time (placeholder: default 2 PM)
        // In production, this would analyze StudySession history for avg start time.
        let historicalStudyHour = historicalAverageStudyHour(modelContext: modelContext)

        // Study-specific check: if user hasn't started study and it's past their usual time
        let studyProgress = progressItems.first(where: { $0.nonNegotiable?.type == .study })
        let studyNotStarted = (studyProgress?.currentValue ?? 0) == 0 && studyProgress != nil
        let studyRemainingMin = max(0, Int((studyProgress?.targetValue ?? 0) - (studyProgress?.currentValue ?? 0)))

        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // Schedule study nudge if past historical study time and study not started
        if studyNotStarted, currentHour >= historicalStudyHour {
            let nudgeTime = now.addingTimeInterval(30 * 60) // 30 min from now
            if nudgeTime < ps5Time {
                let message = if streakDays > 5 {
                    "You're behind on study today. \(studyRemainingMin)min target. Your \(streakDays)-day streak needs this."
                } else {
                    "You haven't started studying yet. \(studyRemainingMin)min left to hit your target. Open Tempo and start a timer."
                }
                notificationService.scheduleAccountabilityEscalation(
                    tier: .gentle,
                    time: nudgeTime,
                    content: message
                )
            }
        }

        // Progressive urgency based on time remaining
        let halfwayPoint = now.addingTimeInterval(timeToPS5 * 0.5) // 50% time remaining
        let quarterPoint = now.addingTimeInterval(timeToPS5 * 0.75) // 25% time remaining
        let tenPercentPoint = now.addingTimeInterval(timeToPS5 * 0.9) // 10% time remaining

        // Gentle reminder at 50% time remaining (if less than half done)
        let completionPct = Double(completedCount) / Double(totalCount)
        if completionPct < 0.5, halfwayPoint > now.addingTimeInterval(60) {
            let body = "\(remaining) task\(remaining == 1 ? "" : "s") remaining. \(formatTimeInterval(timeToPS5 * 0.5)) left. You've got time, but don't waste it."
            notificationService.scheduleAccountabilityEscalation(
                tier: .gentle,
                time: halfwayPoint,
                content: body
            )
        }

        // Firm at 25% time remaining
        if completionPct < 0.75, quarterPoint > now.addingTimeInterval(60) {
            var body = "\(remaining) task\(remaining == 1 ? "" : "s") incomplete. \(formatTimeInterval(timeToPS5 * 0.25)) left."
            if studyRemainingMin > 0 {
                body += " Study: \(studyRemainingMin)min to go."
            }
            body += " Time is running."
            notificationService.scheduleAccountabilityEscalation(
                tier: .firm,
                time: quarterPoint,
                content: body
            )
        }

        // Urgent at 10% time remaining
        if completionPct < 1.0, tenPercentPoint > now.addingTimeInterval(60) {
            let body = if streakDays > 3 {
                "Your \(streakDays)-day streak dies in \(formatTimeInterval(timeToPS5 * 0.1)). \(remaining) task\(remaining == 1 ? "" : "s") left. DO IT NOW."
            } else {
                "\(formatTimeInterval(timeToPS5 * 0.1)) until PS5 time. \(remaining) task\(remaining == 1 ? "" : "s") undone. This is it."
            }
            notificationService.scheduleAccountabilityEscalation(
                tier: .urgent,
                time: tenPercentPoint,
                content: body
            )
        }

        // Streak warning (if streak > 3 and significant tasks remain)
        if streakDays > 3, remaining > 0 {
            let streakWarningTime = ps5Time.addingTimeInterval(-45 * 60) // 45 min before PS5
            if streakWarningTime > now.addingTimeInterval(60) {
                notificationService.scheduleStreakWarning(
                    streakDays: streakDays,
                    tasksRemaining: remaining,
                    time: streakWarningTime
                )
            }
        }
    }

    /// Analyze StudySession history to find the user's average study start hour.
    /// Falls back to 14 (2 PM) if no history exists.
    private func historicalAverageStudyHour(modelContext: ModelContext) -> Int {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        let descriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate { s in s.startTime >= sevenDaysAgo }
        )

        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else {
            return 14 // Default: 2 PM
        }

        let totalHours = sessions.reduce(0) { $0 + calendar.component(.hour, from: $1.startTime) }
        return totalHours / sessions.count
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - End of Day

    func processEndOfDay(modelContext: ModelContext) {
        guard let accountability, let streak = overallStreak else {
            return
        }

        // Update score
        accountability.accountabilityScore = engine.calculateDailyScore(accountability: accountability)

        // Update overall streak
        engine.updateStreak(
            streak: streak,
            dayCompleted: accountability.allComplete,
            override: activeOverride,
            modelContext: modelContext
        )

        // Update per-habit streaks based on each non-negotiable's completion
        for progress in progressItems {
            guard let nnType = progress.nonNegotiable?.type,
                  let habitStreak = habitStreaks[nnType]
            else {
                continue
            }
            engine.updateStreak(
                streak: habitStreak,
                dayCompleted: progress.isCompleted,
                override: activeOverride,
                modelContext: modelContext
            )
        }

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
