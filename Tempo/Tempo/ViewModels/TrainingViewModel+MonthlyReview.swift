//
// TrainingViewModel+MonthlyReview.swift
// Tempo
//
// Monthly review (D4 §17) — due-window detection, interview persistence
// and the Whoop/HealthKit activity aggregation feeding the Sonnet summary.
// Split out of TrainingViewModel.swift to keep it under the SwiftLint
// file/type-body length caps — same instance methods, hosted in an extension.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Monthly Review (D4 §17)

    /// Due = inside the month-boundary window AND the month's summary not yet
    /// generated. An interview saved without a summary (offline) stays due so
    /// the Sonnet call retries on a later open within the window.
    func monthlyReviewDue(modelContext: ModelContext, now: Date = Date()) -> String? {
        guard let key = MonthlyReviewSchedule.dueMonthKey(on: now) else {
            return nil
        }
        if let existing = fetchMonthlyReview(monthKey: key, modelContext: modelContext),
           existing.summaryText != nil
        {
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
        guard let interval = MonthlyReviewSchedule.monthInterval(forKey: monthKey) else {
            return nil
        }
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
                  let actual = session.workoutPlan?.sessionRPE
            else {
                return nil
            }
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
        guard review.summaryText == nil else {
            return false
        }
        guard let apiClient else {
            return false
        }
        guard let data = assembleMonthlyData(monthKey: review.monthKey, modelContext: modelContext) else {
            return false
        }

        let interview = MonthInterviewSnapshot(
            wentWell: review.wentWell,
            struggles: review.struggles,
            niggles: review.niggles,
            subjectiveProgress: review.subjectiveProgress,
            goalsNextMonth: review.goalsNextMonth,
            chosenEmphasis: review.chosenEmphasis?.rawValue
        )
        let coach = MonthlyReviewCoach(apiClient: apiClient)
        guard let text = await coach.summary(data: data, interview: interview) else {
            return false
        }

        review.summaryText = text
        review.summaryGeneratedAt = Date()
        saveGuarded(modelContext, operation: "monthly review")
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
              let start = MonthlyReviewSchedule.nextMonthStart(afterKey: review.monthKey)
        else {
            return
        }
        let day = Calendar.current.startOfDay(for: start)
        let existing = (try? modelContext.fetch(FetchDescriptor<TrainingBlock>())) ?? []
        guard !existing.contains(where: { Calendar.current.startOfDay(for: $0.startDate) == day }) else {
            return
        }
        modelContext.insert(TrainingBlock(emphasis: emphasis, startDate: day))
        saveGuarded(modelContext, operation: "monthly focus")
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

        let activities = await whoop.providesRealData ? ((try? whoop.fetchWorkouts(for: Date())) ?? []) : []
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
        guard let strain = s.strain else {
            return nil
        } // manual entry: no metrics
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
}
