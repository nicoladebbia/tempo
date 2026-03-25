import Foundation
import SwiftData

// MARK: - Daily Accountability State
// Per STATE_MACHINES.md Section 3 — Daily Accountability states.

enum DailyAccountabilityState: String, Codable, Sendable {
    case morningSetup
    case tracking
    case approachingDeadline
    case finalWarning
    case unlocked
    case dayFailed
    case overrideActive
    case review
}

// MARK: - Override Type
// Per MODULE_ACCOUNTABILITY.md Section 13

enum AccountabilityOverrideType: String, Codable, Sendable {
    case restDayFull
    case restDayReduced
    case sickDay
    case mentalHealthDay
    case injuryMode
    case vacationMode
}

// MARK: - Accountability Engine
// Per BUILD_PLAN step 10.1.
// Per STATE_MACHINES.md Section 3 — Daily Accountability state machine.
// Per MODULE_ACCOUNTABILITY.md Sections 8, 9, 13, 15.

final class AccountabilityEngine: @unchecked Sendable {

    // MARK: - Configuration

    /// Default PS5 unlock time (weekdays)
    private let defaultPS5TimeWeekday: DateComponents = {
        var c = DateComponents()
        c.hour = 19
        c.minute = 30
        return c
    }()

    /// Default PS5 unlock time (weekends)
    /// Per MODULE_ACCOUNTABILITY.md Section 8 — Weekend mode defaults to 9:00 PM.
    private let defaultPS5TimeWeekend: DateComponents = {
        var c = DateComponents()
        c.hour = 21
        c.minute = 0
        return c
    }()

    /// Max rest days per month before streak is affected
    /// Per MODULE_ACCOUNTABILITY.md Section 13
    private let maxRestDaysPerMonth = 4

    // MARK: - State Evaluation

    /// Determine the current accountability state for today.
    /// Per STATE_MACHINES.md Section 3 — Daily Accountability state machine transitions.
    func evaluateState(
        accountability: DailyAccountability,
        override: AccountabilityOverrideType?,
        ps5Time: Date
    ) -> DailyAccountabilityState {
        let now = Date()

        // Override takes precedence
        // Per STATE_MACHINES.md Section 3: Any non-terminal → overrideActive
        if override != nil {
            return .overrideActive
        }

        // Already unlocked
        if accountability.leisureUnlocked {
            return .unlocked
        }

        // All complete → unlocked
        if accountability.allComplete {
            return .unlocked
        }

        // Past PS5 time and incomplete → dayFailed
        // Per STATE_MACHINES.md Section 3: finalWarning → dayFailed (PS5 time reached AND tasks incomplete)
        if now >= ps5Time && !accountability.allComplete {
            return .dayFailed
        }

        // Within 30 minutes of PS5 time → finalWarning
        // Per STATE_MACHINES.md Section 3: approachingDeadline → finalWarning (timeToPS5 < 30 min)
        let timeToPS5 = ps5Time.timeIntervalSince(now)
        if timeToPS5 > 0 && timeToPS5 < 30 * 60 {
            return .finalWarning
        }

        // Past 50% of day window and incomplete → approachingDeadline
        // Per STATE_MACHINES.md Section 3: tracking → approachingDeadline (completionPercent < 100 && timeToPS5 < 50% of day window)
        if timeToPS5 > 0 && timeToPS5 < totalDayWindow(ps5Time: ps5Time) * 0.5 {
            return .approachingDeadline
        }

        // Normal tracking
        if accountability.totalCount > 0 {
            return .tracking
        }

        return .morningSetup
    }

    // MARK: - Leisure Unlock

    /// Check if leisure should be unlocked.
    /// Per STATE_MACHINES.md Section 3: tracking/approachingDeadline → unlocked (all complete).
    func checkLeisureUnlock(accountability: DailyAccountability) -> Bool {
        accountability.allComplete
    }

    /// Process an unlock event. Returns true if newly unlocked.
    func processUnlock(
        accountability: DailyAccountability,
        modelContext: ModelContext
    ) -> Bool {
        guard accountability.allComplete && !accountability.leisureUnlocked else {
            return false
        }

        accountability.leisureUnlocked = true
        accountability.unlockedAt = Date()
        try? modelContext.save()
        return true
    }

    // MARK: - Daily Score Calculation

    /// Calculate daily accountability score (0-100).
    /// Per MODULE_ACCOUNTABILITY.md — Score weights each non-negotiable equally.
    func calculateDailyScore(accountability: DailyAccountability) -> Int {
        guard accountability.totalCount > 0 else { return 0 }

        let baseScore = accountability.completionPercentage * 80 // 80 points from completion

        // Time bonus: completed before PS5 time = up to 10 points
        var timeBonus: Double = 0
        if accountability.allComplete, let unlockedAt = accountability.unlockedAt {
            let hour = Calendar.current.component(.hour, from: unlockedAt)
            if hour < 12 {
                timeBonus = 10 // Early bird
            } else if hour < 17 {
                timeBonus = 5
            }
        }

        // No-skip bonus: all items completed (not skipped) = 10 points
        let noSkipBonus: Double = accountability.allComplete ? 10 : 0

        return min(100, Int(baseScore + timeBonus + noSkipBonus))
    }

    // MARK: - Non-Negotiable Management

    /// Load today's active non-negotiables and create progress entries.
    /// Per MODULE_ACCOUNTABILITY.md Section 15.1.
    func loadTodayNonNegotiables(
        modelContext: ModelContext
    ) -> DailyAccountability {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        // Check for existing
        let descriptor = FetchDescriptor<DailyAccountability>(
            predicate: #Predicate { da in
                da.date >= today && da.date < tomorrow
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        // Create new
        let accountability = DailyAccountability(date: today)
        modelContext.insert(accountability)

        // Fetch active non-negotiables for today's day of week
        let weekday = Calendar.current.component(.weekday, from: today)
        let allNonNegs = (try? modelContext.fetch(FetchDescriptor<NonNegotiable>())) ?? []

        let activeToday = allNonNegs.filter { nn in
            nn.isActive && nn.activeDays.isActive(on: weekday)
        }

        // Create progress entries
        for nn in activeToday.sorted(by: { $0.order < $1.order }) {
            let progress = NonNegotiableProgress(
                date: today,
                targetValue: adjustedTarget(for: nn, date: today),
                nonNegotiable: nn,
                dailyAccountability: accountability
            )
            modelContext.insert(progress)
        }

        try? modelContext.save()
        return accountability
    }

    /// Update progress for a non-negotiable.
    /// Per STATE_MACHINES.md Section 6 — notStarted → inProgress → completed.
    func updateProgress(
        progress: NonNegotiableProgress,
        newValue: Double,
        modelContext: ModelContext
    ) {
        progress.currentValue = newValue

        // Check completion
        if newValue >= progress.targetValue && !progress.isCompleted {
            progress.isCompleted = true
            progress.completedAt = Date()
        } else if newValue < progress.targetValue && progress.isCompleted {
            // Target increased mid-day — re-open
            // Per MODULE_ACCOUNTABILITY.md Section 15.12
            progress.isCompleted = false
            progress.completedAt = nil
        }

        try? modelContext.save()
    }

    /// Mark a non-negotiable as skipped.
    /// Per MODULE_ACCOUNTABILITY.md Section 15.3 — Skip flow.
    func skipNonNegotiable(
        progress: NonNegotiableProgress,
        modelContext: ModelContext
    ) {
        progress.isCompleted = true
        progress.completedAt = Date()
        // Mark as skip by setting value to a special sentinel
        // (currentValue stays at current; isCompleted = true signals skip if currentValue < targetValue)
        try? modelContext.save()
    }

    // MARK: - Rest Day / Sick Day Handling

    /// Apply rest day override — marks training as automatically satisfied.
    /// Per MODULE_ACCOUNTABILITY.md Section 13.
    func applyRestDayOverride(
        accountability: DailyAccountability,
        type: AccountabilityOverrideType,
        modelContext: ModelContext
    ) {
        let progress = accountability.nonNegotiableProgress ?? []

        switch type {
        case .restDayFull:
            // All non-negotiables marked as skipped
            for p in progress {
                p.isCompleted = true
                p.completedAt = Date()
            }

        case .restDayReduced:
            // Training skipped, study halved, meals remain
            for p in progress {
                guard let nn = p.nonNegotiable else { continue }
                if nn.type == .train {
                    p.isCompleted = true
                    p.completedAt = Date()
                } else if nn.type == .study {
                    p.targetValue = max(30, p.targetValue / 2) // min 30 min
                }
            }

        case .sickDay:
            // Training skipped, study optional (30 min max), meals reduced to 2
            for p in progress {
                guard let nn = p.nonNegotiable else { continue }
                if nn.type == .train {
                    p.isCompleted = true
                    p.completedAt = Date()
                } else if nn.type == .study {
                    p.targetValue = 30
                } else if nn.type == .meals {
                    p.targetValue = 2
                }
            }

        case .mentalHealthDay:
            // Study optional (30 min), training optional, meals at full
            // Per MODULE_ACCOUNTABILITY.md Section 13.3 — zero tough love
            for p in progress {
                guard let nn = p.nonNegotiable else { continue }
                if nn.type == .train || nn.type == .study {
                    p.targetValue = 30
                }
            }

        case .injuryMode:
            // Training skipped automatically, everything else at full
            // Per MODULE_ACCOUNTABILITY.md Section 13.4
            for p in progress {
                guard let nn = p.nonNegotiable else { continue }
                if nn.type == .train {
                    p.isCompleted = true
                    p.completedAt = Date()
                }
            }

        case .vacationMode:
            // All suspended
            for p in progress {
                p.isCompleted = true
                p.completedAt = Date()
            }
        }

        try? modelContext.save()
    }

    // MARK: - Streak Management

    /// Update streak after a day's accountability is evaluated.
    /// Per STATE_MACHINES.md Section 7 — Streak state machine.
    func updateStreak(
        streak: Streak,
        dayCompleted: Bool,
        override: AccountabilityOverrideType?,
        modelContext: ModelContext
    ) {
        // Override days don't count but don't break
        // Per STATE_MACHINES.md Section 7: active(N) → active(N) on rest/sick day
        if override != nil {
            // Streak preserved, no increment
            streak.lastCompletedDate = Calendar.current.startOfDay(for: Date())
            try? modelContext.save()
            return
        }

        if dayCompleted {
            streak.recordCompletion()
        } else {
            // Check if we should use a freeze
            if streak.canFreeze && streak.currentCount > 0 {
                _ = streak.useFreeze()
            } else if streak.currentCount > 0 {
                streak.breakStreak()
            }
        }

        try? modelContext.save()
    }

    /// Check if streak is at risk (< 2h to midnight, tasks incomplete).
    /// Per STATE_MACHINES.md Section 7: active(N) → atRisk
    func isStreakAtRisk(
        accountability: DailyAccountability,
        streak: Streak
    ) -> Bool {
        guard streak.currentCount > 0 && !accountability.allComplete else { return false }
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now)!)
        return midnight.timeIntervalSince(now) < 2 * 3600
    }

    /// Check if a streak milestone was reached.
    /// Per STATE_MACHINES.md Section 7 — Milestone system.
    func streakMilestone(count: Int) -> StreakMilestone? {
        switch count {
        case 3: return .threeDay
        case 5: return .fiveDay
        case 7: return .oneWeek
        case 14: return .twoWeek
        case 21: return .threeWeek
        case 30: return .oneMonth
        case 50: return .elite
        case 100: return .century
        default: return nil
        }
    }

    // MARK: - Weekend Mode
    // Per MODULE_ACCOUNTABILITY.md Section 8

    /// Check if today is a weekend.
    func isWeekend(date: Date = Date()) -> Bool {
        Calendar.current.isDateInWeekend(date)
    }

    /// Get the PS5 time for a given date.
    func ps5Time(for date: Date = Date()) -> Date {
        let components = isWeekend(date: date) ? defaultPS5TimeWeekend : defaultPS5TimeWeekday
        return Calendar.current.date(
            bySettingHour: components.hour ?? 19,
            minute: components.minute ?? 30,
            second: 0,
            of: date
        ) ?? date
    }

    // MARK: - Target Adjustments

    // MARK: - Exam-Aware Study Target
    // Per BUILD_PLAN step 13.2 — Exam within 7 days → study target increased by 50%.

    /// The number of days until the next exam. Set by DashboardViewModel from calendar data.
    /// When an exam is within 7 days, study targets increase by 50%.
    var daysToNextExam: Int?

    /// Adjust target for weekend mode and exam proximity.
    /// Per MODULE_ACCOUNTABILITY.md Section 8 — weekend targets configurable per non-negotiable.
    /// Per BUILD_PLAN step 13.2 — exam within 7 days → study target +50%.
    private func adjustedTarget(for nn: NonNegotiable, date: Date) -> Double {
        var target = nn.targetValue

        if isWeekend(date: date) && nn.type == .study {
            target = target / 2
        }

        // Exam proximity boost: +50% study when exam within 7 days
        if nn.type == .study, let days = daysToNextExam, days <= 7 {
            target = target * 1.5
        }

        return target
    }

    // MARK: - Helpers

    /// Total day window in seconds (from 8 AM to PS5 time).
    private func totalDayWindow(ps5Time: Date) -> TimeInterval {
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: 8, minute: 0, second: 0, of: ps5Time) ?? ps5Time
        return max(1, ps5Time.timeIntervalSince(dayStart))
    }
}

// MARK: - Streak Milestone
// Per STATE_MACHINES.md Section 7 — Milestone system.

enum StreakMilestone: Int, CaseIterable, Sendable {
    case threeDay = 3
    case fiveDay = 5
    case oneWeek = 7
    case twoWeek = 14
    case threeWeek = 21
    case oneMonth = 30
    case elite = 50
    case century = 100

    var title: String {
        switch self {
        case .threeDay: "3-Day Streak"
        case .fiveDay: "5-Day Streak"
        case .oneWeek: "Perfect Week"
        case .twoWeek: "Two-Week Streak"
        case .threeWeek: "21-Day Milestone"
        case .oneMonth: "Monthly Champion"
        case .elite: "Elite"
        case .century: "Century"
        }
    }

    var xpBonus: Int {
        switch self {
        case .threeDay: 0
        case .fiveDay: 0
        case .oneWeek: 100
        case .twoWeek: 150
        case .threeWeek: 200
        case .oneMonth: 300
        case .elite: 500
        case .century: 1000
        }
    }

    /// Whether this milestone grants a bonus hour (PS5 time 1h earlier).
    var grantsBonusHour: Bool {
        self == .fiveDay
    }
}
