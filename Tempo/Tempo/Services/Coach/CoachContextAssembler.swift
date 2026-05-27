//
// CoachContextAssembler.swift
// Tempo
//
// Coach v2.1 Phase 5 — builds the ~3.7K-token system prompt block per turn.
//
// Aggregates:
//   - <identity>           from UserProfile + DietaryProfile
//   - <preferences>        from PreferenceRetriever (top-N filtered + ranked)
//   - <outcomes>           recent LearnedOutcome rows for recall + grading
//   - <today-live>         today's recovery / planned meals / workout / steps
//   - <today-calendar>     EventKit read (Phase 5.8)
//   - <backward-7-days>    compact daily strips from existing models
//   - <forward-7-days>     planned meals + workouts
//   - <goal-progress>      weight trajectory vs target (Phase 5.9)
//   - <recent-conversations> 5-most-recent CoachConversation summaries
//                          (deferred wiring — Phase 6 ships CoachConversation
//                          so we accept a pre-built list here)
//
// Pure logic. No AI calls. Today's HK + Whoop snapshots are passed in as
// values — keeps Phase 5 testable and decoupled from those services.
// Phase 6's CoachService is the caller that fills the snapshot live.
//
// Per .plans/coach-v2.1/03-services-and-data-flow.md and §04-ai-architecture.md
// "System prompt structure".
//

import Foundation
import SwiftData

// MARK: - CoachContextAssembler

enum CoachContextAssembler {
    /// Hard token budget at p95 user data per the architecture doc.
    /// `render()` enforces by pruning sections in order on overflow.
    static let targetTokenBudget = 3700

    /// Conservative chars-per-token estimate for the self-check.
    static let charsPerToken = 4

    /// Primary entry point. Returns a fully-rendered `CoachContextSnapshot`
    /// suitable for the system-prompt slot in a `/v1/nutrition-ai/coach/chat`
    /// request. All inputs are passive snapshots — the assembler does NOT
    /// fire any network or service calls itself.
    @MainActor
    static func assemble(
        modelContext context: ModelContext,
        today: Date = Date(),
        userMessage: String? = nil,
        todayLive: TodayLiveSnapshot,
        calendarEvents: [CalendarEventSummary] = [],
        recentConversationSummaries: [ConversationSummary] = [],
        calendar: Calendar = .current
    ) -> CoachContextSnapshot {
        let identity = makeIdentity(in: context)
        let dayType = todayLive.dayType
        let preferences = PreferenceRetriever.retrieve(
            forContext: context,
            userMessage: userMessage,
            today: today,
            dayType: dayType,
            calendar: calendar
        )
        let outcomes = recentOutcomes(in: context, today: today)
        let backward = makeBackwardWindow(in: context, today: today, calendar: calendar)
        let forward = makeForwardWindow(in: context, today: today, calendar: calendar)
        let goal = makeGoalProgress(in: context, today: today, calendar: calendar)

        return CoachContextSnapshot(
            identity: identity,
            preferences: preferences,
            outcomes: outcomes,
            todayLive: todayLive,
            calendarEvents: calendarEvents,
            backwardWindow: backward,
            forwardWindow: forward,
            goalProgress: goal,
            conversationSummaries: recentConversationSummaries
        )
    }

    // MARK: - Identity

    @MainActor
    static func makeIdentity(in context: ModelContext) -> IdentityBlock {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let diet = (try? context.fetch(FetchDescriptor<DietaryProfile>()))?.first

        return IdentityBlock(
            displayName: profile?.displayName ?? "User",
            age: profile?.age,
            sport: profile?.identityLabel,
            primaryGoal: diet?.primaryGoal.displayName,
            currentWeightKg: diet?.currentWeightKg ?? profile?.weightKg,
            heightCm: profile?.heightCm
        )
    }

    // MARK: - Outcomes (recent graded only)

    @MainActor
    static func recentOutcomes(
        in context: ModelContext,
        today: Date,
        windowDays: Int = 14
    ) -> [LearnedOutcome] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: today) else {
            return []
        }
        let descriptor = FetchDescriptor<LearnedOutcome>(
            predicate: #Predicate<LearnedOutcome> { row in
                row.gradedAt != nil && row.decisionDate >= cutoff
            }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.sorted { $0.decisionDate > $1.decisionDate }
    }

    // MARK: - Backward window (last 7 days)

    @MainActor
    static func makeBackwardWindow(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) -> [BackwardDay] {
        let dayStart = calendar.startOfDay(for: today)
        guard let windowStart = calendar.date(byAdding: .day, value: -7, to: dayStart) else {
            return []
        }
        let mealDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= windowStart && meal.dayDate < dayStart
            }
        )
        let meals = (try? context.fetch(mealDescriptor)) ?? []
        let recoveryDescriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate<DailyRecovery> { row in
                row.date >= windowStart && row.date < dayStart
            }
        )
        let recoveries = (try? context.fetch(recoveryDescriptor)) ?? []
        let workoutDescriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { plan in
                plan.date >= windowStart && plan.date < dayStart
            }
        )
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []

        var days: [BackwardDay] = []
        var cursor = windowStart
        while cursor < dayStart {
            let dayMeals = meals.filter {
                calendar.isDate($0.dayDate, inSameDayAs: cursor)
            }
            let dayWorkout = workouts.first { calendar.isDate($0.date, inSameDayAs: cursor) }
            let dayRecovery = recoveries.first { calendar.isDate($0.date, inSameDayAs: cursor) }

            let plannedKcal = dayMeals.reduce(0) { $0 + $1.totalCalories }
            let eatenKcal = dayMeals.filter { $0.status == .eaten || $0.status == .modified }
                .reduce(0) { $0 + $1.totalCalories }
            let skipped = dayMeals.filter { $0.status == .skipped }.count
            let deviations = abs(plannedKcal - eatenKcal) > 250 || skipped > 0

            days.append(BackwardDay(
                date: cursor,
                dayType: dayWorkout?.type,
                plannedMealCount: dayMeals.count,
                eatenMealCount: dayMeals.filter { $0.status == .eaten || $0.status == .modified }.count,
                skippedMealCount: skipped,
                plannedKcal: plannedKcal,
                eatenKcal: eatenKcal,
                workoutStatus: dayWorkout?.status,
                sleepHours: dayRecovery?.sleepHours,
                recoveryScore: dayRecovery?.recoveryScore,
                deviationsFlag: deviations
            ))

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    // MARK: - Forward window (next 7 days)

    @MainActor
    static func makeForwardWindow(
        in context: ModelContext,
        today: Date,
        calendar: Calendar
    ) -> [ForwardDay] {
        let dayStart = calendar.startOfDay(for: today)
        guard let dayAfter = calendar.date(byAdding: .day, value: 1, to: dayStart),
              let windowEnd = calendar.date(byAdding: .day, value: 8, to: dayStart)
        else { return [] }

        let mealDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= dayAfter && meal.dayDate < windowEnd
            }
        )
        let meals = (try? context.fetch(mealDescriptor)) ?? []
        let workoutDescriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { plan in
                plan.date >= dayAfter && plan.date < windowEnd
            }
        )
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []

        var days: [ForwardDay] = []
        var cursor = dayAfter
        while cursor < windowEnd {
            let dayMeals = meals.filter { calendar.isDate($0.dayDate, inSameDayAs: cursor) }
            let dayWorkout = workouts.first { calendar.isDate($0.date, inSameDayAs: cursor) }
            days.append(ForwardDay(
                date: cursor,
                dayType: dayWorkout?.type,
                plannedMealCount: dayMeals.count,
                plannedKcal: dayMeals.reduce(0) { $0 + $1.totalCalories }
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    // MARK: - Goal progress

    @MainActor
    static func makeGoalProgress(
        in context: ModelContext,
        today _: Date,
        calendar _: Calendar
    ) -> GoalProgressBlock? {
        guard let diet = (try? context.fetch(FetchDescriptor<DietaryProfile>()))?.first else {
            return nil
        }
        return GoalProgressBlock(
            primaryGoal: diet.primaryGoal.displayName,
            currentWeightKg: diet.currentWeightKg,
            // Target + trajectory bound to a follow-up phase (5.x or 7.5)
            // when DietaryProfile gains target-weight + weight-history fields.
            targetWeightKg: nil,
            weeklyChangeKg: nil,
            trajectoryLabel: nil
        )
    }
}

// MARK: - Snapshot types

struct CoachContextSnapshot: Equatable {
    let identity: IdentityBlock
    let preferences: [LearnedPreference]
    let outcomes: [LearnedOutcome]
    let todayLive: TodayLiveSnapshot
    let calendarEvents: [CalendarEventSummary]
    let backwardWindow: [BackwardDay]
    let forwardWindow: [ForwardDay]
    let goalProgress: GoalProgressBlock?
    let conversationSummaries: [ConversationSummary]

    static func == (lhs: CoachContextSnapshot, rhs: CoachContextSnapshot) -> Bool {
        lhs.identity == rhs.identity
            && lhs.preferences.map(\.id) == rhs.preferences.map(\.id)
            && lhs.outcomes.map(\.id) == rhs.outcomes.map(\.id)
            && lhs.todayLive == rhs.todayLive
            && lhs.calendarEvents == rhs.calendarEvents
            && lhs.backwardWindow == rhs.backwardWindow
            && lhs.forwardWindow == rhs.forwardWindow
            && lhs.goalProgress == rhs.goalProgress
            && lhs.conversationSummaries == rhs.conversationSummaries
    }
}

struct IdentityBlock: Equatable {
    let displayName: String
    let age: Int?
    let sport: String?
    let primaryGoal: String?
    let currentWeightKg: Double?
    let heightCm: Double?
}

/// Live values for "today" passed in by the caller. Phase 6's CoachService
/// fills this with WhoopService + HealthKitService + planner reads.
struct TodayLiveSnapshot: Equatable {
    let date: Date
    let dayType: DayType?
    let recoveryScore: Double?
    let recoveryZone: String?
    let hrvMs: Double?
    let restingHR: Double?
    let sleepHoursLastNight: Double?
    let stepsSoFar: Int?
    let plannedMealCount: Int
    let loggedKcalSoFar: Int
    let targetKcal: Int?
    let workoutTitle: String?
    let workoutTime: String?
}

struct CalendarEventSummary: Equatable {
    let title: String
    let startHHmm: String
    let endHHmm: String

    init(_ event: CalendarEvent, calendar _: Calendar = .current) {
        self.title = event.title
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.startHHmm = formatter.string(from: event.startDate)
        self.endHHmm = formatter.string(from: event.endDate)
    }

    init(title: String, startHHmm: String, endHHmm: String) {
        self.title = title
        self.startHHmm = startHHmm
        self.endHHmm = endHHmm
    }
}

struct BackwardDay: Equatable {
    let date: Date
    let dayType: WorkoutType?
    let plannedMealCount: Int
    let eatenMealCount: Int
    let skippedMealCount: Int
    let plannedKcal: Double
    let eatenKcal: Double
    let workoutStatus: WorkoutStatus?
    let sleepHours: Double?
    let recoveryScore: Double?
    let deviationsFlag: Bool
}

struct ForwardDay: Equatable {
    let date: Date
    let dayType: WorkoutType?
    let plannedMealCount: Int
    let plannedKcal: Double
}

struct GoalProgressBlock: Equatable {
    let primaryGoal: String
    let currentWeightKg: Double
    let targetWeightKg: Double?
    let weeklyChangeKg: Double?
    let trajectoryLabel: String?
}

struct ConversationSummary: Equatable {
    let id: UUID
    let endedAt: Date
    let titleSummary: String
}

// MARK: - Rendering

extension CoachContextSnapshot {
    /// Renders the snapshot as the system-prompt body. Sections are
    /// delimited by lowercase tag pairs (`<identity>...</identity>`) so the
    /// agent can reason about them.
    ///
    /// Token-budget self-check: if the raw render exceeds the budget,
    /// prune in this order (least → most load-bearing):
    ///   1. oldest conversation summaries
    ///   2. forward window detail (collapsed to header-only)
    ///   3. backward window detail (collapsed to header-only)
    ///   4. preferences (keep top-N by ranking already applied in retriever)
    func render(budget: Int = CoachContextAssembler.targetTokenBudget) -> String {
        // Local render state. All pruning happens here, not on the source
        // snapshot — keeps CoachContextSnapshot a pure value type.
        var summaries = conversationSummaries
        var collapseForward = false
        var collapseBackward = false
        var preferenceCount = preferences.count

        var rendered = renderRaw(
            preferenceCount: preferenceCount,
            summaries: summaries,
            collapseForward: collapseForward,
            collapseBackward: collapseBackward
        )
        var estimatedTokens = rendered.count / CoachContextAssembler.charsPerToken

        // Pass 1: trim conversation summaries oldest-first.
        while estimatedTokens > budget && !summaries.isEmpty {
            summaries.removeFirst()
            rendered = renderRaw(
                preferenceCount: preferenceCount,
                summaries: summaries,
                collapseForward: collapseForward,
                collapseBackward: collapseBackward
            )
            estimatedTokens = rendered.count / CoachContextAssembler.charsPerToken
        }

        // Pass 2: collapse forward window.
        if estimatedTokens > budget {
            collapseForward = true
            rendered = renderRaw(
                preferenceCount: preferenceCount,
                summaries: summaries,
                collapseForward: collapseForward,
                collapseBackward: collapseBackward
            )
            estimatedTokens = rendered.count / CoachContextAssembler.charsPerToken
        }

        // Pass 3: collapse backward window.
        if estimatedTokens > budget {
            collapseBackward = true
            rendered = renderRaw(
                preferenceCount: preferenceCount,
                summaries: summaries,
                collapseForward: collapseForward,
                collapseBackward: collapseBackward
            )
            estimatedTokens = rendered.count / CoachContextAssembler.charsPerToken
        }

        // Pass 4: trim preference tail until under budget (keep at least 5).
        while estimatedTokens > budget && preferenceCount > 5 {
            preferenceCount -= 1
            rendered = renderRaw(
                preferenceCount: preferenceCount,
                summaries: summaries,
                collapseForward: collapseForward,
                collapseBackward: collapseBackward
            )
            estimatedTokens = rendered.count / CoachContextAssembler.charsPerToken
        }

        return rendered
    }

    // MARK: - Render pipeline

    fileprivate func renderRaw(
        preferenceCount: Int,
        summaries: [ConversationSummary],
        collapseForward: Bool,
        collapseBackward: Bool
    ) -> String {
        var lines: [String] = []
        lines.append("<identity>")
        lines.append("Name: \(identity.displayName)")
        if let age = identity.age { lines.append("Age: \(age)") }
        if let sport = identity.sport { lines.append("Sport: \(sport)") }
        if let goal = identity.primaryGoal { lines.append("Goal: \(goal)") }
        if let weight = identity.currentWeightKg {
            lines.append(String(format: "Current weight: %.1fkg", weight))
        }
        if let height = identity.heightCm {
            lines.append(String(format: "Height: %.0fcm", height))
        }
        lines.append("</identity>")
        lines.append("")

        if let goalBlock = goalProgress {
            lines.append("<goal-progress>")
            lines.append("Goal: \(goalBlock.primaryGoal)")
            lines.append(String(format: "Current weight: %.1fkg", goalBlock.currentWeightKg))
            if let target = goalBlock.targetWeightKg {
                lines.append(String(format: "Target: %.1fkg", target))
            }
            if let weekly = goalBlock.weeklyChangeKg {
                lines.append(String(format: "Weekly trend: %+.2fkg/week", weekly))
            }
            if let trajectory = goalBlock.trajectoryLabel {
                lines.append("Trajectory: \(trajectory)")
            }
            lines.append("</goal-progress>")
            lines.append("")
        }

        lines.append("<preferences-relevant-to-this-message>")
        let prefsToRender = Array(preferences.prefix(preferenceCount))
        for pref in prefsToRender {
            let id = pref.id.uuidString.prefix(4).lowercased()
            let confInt = Int((pref.confidence * 100).rounded())
            lines.append("pref_\(id) [conf \(confInt)%, \(pref.scope.rawValue), \(pref.polarity.rawValue)]: \(pref.text)")
        }
        if prefsToRender.isEmpty {
            lines.append("(none on file yet — Coach is still learning your patterns)")
        }
        lines.append("</preferences-relevant-to-this-message>")
        lines.append("")

        if !outcomes.isEmpty {
            lines.append("<outcomes>")
            for outcome in outcomes.prefix(8) {
                let outcomeLabel = outcome.outcome?.rawValue ?? "unclear"
                lines.append("[\(outcome.actionToolName) \(outcomeLabel)] \(outcome.actionSummary)")
                if let evidence = outcome.evidence {
                    lines.append("  → \(evidence)")
                }
            }
            lines.append("</outcomes>")
            lines.append("")
        }

        lines.append("<today-live>")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd (EEEE)"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        lines.append("Date: \(dateFormatter.string(from: todayLive.date))")
        if let dayType = todayLive.dayType {
            lines.append("Day type: \(dayType.rawValue)")
        }
        if let r = todayLive.recoveryScore {
            let zone = todayLive.recoveryZone.map { " (\($0))" } ?? ""
            lines.append(String(format: "Whoop recovery: %.0f%%\(zone)", r))
        }
        if let hrv = todayLive.hrvMs {
            lines.append(String(format: "HRV: %.1fms", hrv))
        }
        if let rhr = todayLive.restingHR {
            lines.append(String(format: "RHR: %.0fbpm", rhr))
        }
        if let sleep = todayLive.sleepHoursLastNight {
            lines.append(String(format: "Last night sleep: %.1fh", sleep))
        }
        if let steps = todayLive.stepsSoFar {
            lines.append("Steps so far: \(steps)")
        }
        lines.append("Planned meals: \(todayLive.plannedMealCount)")
        if let target = todayLive.targetKcal {
            lines.append("Logged kcal: \(todayLive.loggedKcalSoFar) / \(target)")
        } else {
            lines.append("Logged kcal: \(todayLive.loggedKcalSoFar)")
        }
        if let title = todayLive.workoutTitle {
            let when = todayLive.workoutTime.map { " @ \($0)" } ?? ""
            lines.append("Planned workout: \(title)\(when)")
        }
        if !calendarEvents.isEmpty {
            let events = calendarEvents
                .map { "\($0.title) \($0.startHHmm)–\($0.endHHmm)" }
                .joined(separator: ", ")
            lines.append("Calendar events today: \(events)")
        }
        lines.append("</today-live>")
        lines.append("")

        let dayCompactFormatter = DateFormatter()
        dayCompactFormatter.dateFormat = "yyyy-MM-dd (E)"
        dayCompactFormatter.locale = Locale(identifier: "en_US_POSIX")

        lines.append("<backward-7-days>")
        if collapseBackward {
            lines.append("\(backwardWindow.count) days summarized — see prior context if needed.")
        } else {
            for day in backwardWindow {
                let dateStr = dayCompactFormatter.string(from: day.date)
                let typeStr = day.dayType.map { ", \($0.rawValue)" } ?? ""
                let workoutStr = day.workoutStatus.map { ". Workout: \($0.rawValue)" } ?? ""
                let sleepStr = day.sleepHours.map { String(format: ". Sleep %.1fh", $0) } ?? ""
                let kcalStr = ". Logged \(Int(day.eatenKcal))/\(Int(day.plannedKcal))kcal"
                let flag = day.deviationsFlag ? " (deviations)" : ""
                lines.append("\(dateStr)\(typeStr): \(day.eatenMealCount)/\(day.plannedMealCount) meals\(kcalStr)\(workoutStr)\(sleepStr)\(flag)")
            }
        }
        lines.append("</backward-7-days>")
        lines.append("")

        lines.append("<forward-7-days>")
        if collapseForward {
            lines.append("\(forwardWindow.count) days planned — request details inline if needed.")
        } else {
            for day in forwardWindow {
                let dateStr = dayCompactFormatter.string(from: day.date)
                let typeStr = day.dayType.map { ", \($0.rawValue)" } ?? ""
                lines.append("\(dateStr)\(typeStr): \(day.plannedMealCount) meals, \(Int(day.plannedKcal))kcal target")
            }
        }
        lines.append("</forward-7-days>")
        lines.append("")

        if !summaries.isEmpty {
            lines.append("<recent-conversations>")
            for summary in summaries.prefix(5) {
                lines.append("[\(summary.endedAt.formatted(.iso8601.year().month().day()))] \(summary.titleSummary)")
            }
            lines.append("</recent-conversations>")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
