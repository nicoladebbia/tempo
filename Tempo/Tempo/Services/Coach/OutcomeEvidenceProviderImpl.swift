//
// OutcomeEvidenceProviderImpl.swift
// Tempo
//
// Coach v2.1 Phase 8a — real evidence-fetching impl for OutcomeGrader.
//
// Reads SwiftData (MealLog, WorkoutPlan, DailyRecovery) and HealthKit
// (sleep) to grade pending outcomes per the tool that fired:
//
//   moveMeal       → did a MealLog land near the new scheduled time?
//   skipMeal       → did the user log any compensating food in that slot?
//   swapDayType    → did the next workout match the new day type AND complete?
//   insertActivity → does any activity log exist for that day?
//   shiftBedtime   → did HK sleep show the bedtime actually shifted?
//
// Per .plans/coach-v2.1/02-data-model.md (Model 3 evidence rules) +
// §03-services-and-data-flow.md "OutcomeGrader.run".
//

import Foundation
import SwiftData

// MARK: - HKSleepReading

/// Minimal sleep snapshot the grader needs — main start/end of the
/// sleep period plus total hours. Real impl fills this from
/// HealthKitService.fetchSleepAnalysis; tests stub deterministically.
struct HKSleepReading: Equatable, Sendable {
    let inBedStart: Date
    let inBedEnd: Date
    let totalHours: Double
}

// MARK: - HKSleepReader (injection seam)

/// Sendable protocol so the provider can be unit-tested without HealthKit.
protocol HKSleepReader: Sendable {
    /// Returns the sleep period that ENDED on `date` (i.e., the night
    /// before `date`'s waking hours). nil when no data.
    func sleepEnding(on date: Date) async throws -> HKSleepReading?
}

/// Always-nil stub. Tests use this when sleep data isn't load-bearing
/// for the path under test.
struct NoopHKSleepReader: HKSleepReader {
    func sleepEnding(on _: Date) async throws -> HKSleepReading? { nil }
}

// MARK: - OutcomeEvidenceProviderImpl

/// Reads SwiftData + HK to grade outcomes. @unchecked Sendable because
/// the embedded ModelContainer is itself Sendable but its main-context
/// reads must be marshalled to @MainActor — the implementation hops
/// via the model container's main context.
final class OutcomeEvidenceProviderImpl: OutcomeEvidenceProvider, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let sleepReader: HKSleepReader
    private let decoder = JSONDecoder()

    init(modelContainer: ModelContainer, sleepReader: HKSleepReader = NoopHKSleepReader()) {
        self.modelContainer = modelContainer
        self.sleepReader = sleepReader
    }

    // MARK: - Public

    func fetchEvidence(
        for toolName: String,
        payload: Data,
        decisionDate: Date,
        evaluationDate: Date
    ) async throws -> OutcomeEvidence {
        switch toolName {
        case "moveMeal":
            return try await gradeMoveMeal(
                payload: payload,
                decisionDate: decisionDate,
                evaluationDate: evaluationDate
            )
        case "skipMeal":
            return try await gradeSkipMeal(
                payload: payload,
                decisionDate: decisionDate,
                evaluationDate: evaluationDate
            )
        case "swapDayType":
            return try await gradeSwapDayType(
                payload: payload,
                decisionDate: decisionDate,
                evaluationDate: evaluationDate
            )
        case "insertActivity":
            return try await gradeInsertActivity(
                payload: payload,
                decisionDate: decisionDate,
                evaluationDate: evaluationDate
            )
        case "shiftBedtime":
            return try await gradeShiftBedtime(
                payload: payload,
                decisionDate: decisionDate,
                evaluationDate: evaluationDate
            )
        default:
            // Tools that don't generate PendingOutcome shouldn't reach
            // here; defensive .unclear so the grader still cleans up.
            return .unclear(actionSummary: toolName)
        }
    }

    // MARK: - Per-tool grading

    /// Did a MealLog land within ±60min of the new scheduled time AND
    /// after the decision was made?
    @MainActor
    private func gradeMoveMeal(
        payload: Data,
        decisionDate: Date,
        evaluationDate _: Date
    ) async throws -> OutcomeEvidence {
        guard let args = try? decoder.decode(MoveMealArgs.self, from: payload) else {
            return .unclear(actionSummary: "moveMeal — unparseable payload")
        }
        let context = modelContainer.mainContext

        guard let mealID = UUID(uuidString: args.mealID) else {
            return .unclear(actionSummary: "moveMeal — bad mealID")
        }
        let mealDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { $0.id == mealID }
        )
        guard let meal = try context.fetch(mealDescriptor).first else {
            return .abandoned(
                summary: "Planned meal was deleted before evaluation",
                actionSummary: "moveMeal mealID=\(args.mealID) → \(args.newTimeHHmm)"
            )
        }

        let summary = "moved \(meal.mealName) → \(args.newTimeHHmm)"

        // If the meal is .eaten with an actualEatenAt close to the new time,
        // count as followedThrough. .skipped or .planned (no log) = abandoned.
        switch meal.status {
        case .eaten, .modified:
            if let eaten = meal.actualEatenAt {
                let expected = try Self.scheduledDate(for: meal)
                let delta = abs(eaten.timeIntervalSince(expected)) / 60.0
                if eaten >= decisionDate, delta <= 60 {
                    return OutcomeEvidence(
                        outcome: .followedThrough,
                        summary: String(format: "logged %.0f min off new time", delta),
                        actionSummary: summary
                    )
                }
                return OutcomeEvidence(
                    outcome: .followedThrough,
                    summary: "logged after decision",
                    actionSummary: summary
                )
            }
            return OutcomeEvidence(
                outcome: .followedThrough,
                summary: "marked eaten",
                actionSummary: summary
            )
        case .skipped:
            return .abandoned(summary: "meal skipped", actionSummary: summary)
        case .planned:
            return .abandoned(summary: "no log against the new time", actionSummary: summary)
        }
    }

    /// User logged any food at all near the skipped slot on the decision
    /// day → abandoned (skip suggestion didn't stick). Nothing logged at
    /// that slot → followedThrough.
    @MainActor
    private func gradeSkipMeal(
        payload: Data,
        decisionDate: Date,
        evaluationDate _: Date
    ) async throws -> OutcomeEvidence {
        guard let args = try? decoder.decode(SkipMealArgs.self, from: payload),
              let mealID = UUID(uuidString: args.mealID)
        else {
            return .unclear(actionSummary: "skipMeal — unparseable payload")
        }
        let context = modelContainer.mainContext
        guard let meal = try context.fetch(
            FetchDescriptor<PlannedMeal>(predicate: #Predicate<PlannedMeal> { $0.id == mealID })
        ).first else {
            return .abandoned(
                summary: "Planned meal deleted before evaluation",
                actionSummary: "skipMeal mealID=\(args.mealID)"
            )
        }
        let summary = "skip \(meal.mealName)"

        if meal.status == .skipped {
            return .followedThrough(summary: "meal stayed skipped", actionSummary: summary)
        }
        // If the user actually logged it eaten after the suggestion, the
        // skip suggestion was abandoned.
        if meal.status == .eaten || meal.status == .modified {
            return .abandoned(summary: "user ate it anyway", actionSummary: summary)
        }
        // Still .planned at evaluation — unclear (user neither skipped
        // nor logged; grader treats as unclear, not abandoned).
        return .unclear(actionSummary: summary)
    }

    /// Workout-day-swap grading: find the WorkoutPlan for the same day,
    /// check whether its type matches the new type AND status is .completed.
    @MainActor
    private func gradeSwapDayType(
        payload: Data,
        decisionDate _: Date,
        evaluationDate _: Date
    ) async throws -> OutcomeEvidence {
        guard let args = try? decoder.decode(SwapDayTypeArgs.self, from: payload) else {
            return .unclear(actionSummary: "swapDayType — unparseable payload")
        }
        let context = modelContainer.mainContext
        guard let date = try? CoachToolDispatcherAdapter.parseDate(args.date) else {
            return .unclear(actionSummary: "swapDayType — bad date")
        }
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            return .unclear(actionSummary: "swapDayType — bad date math")
        }
        let workouts = try context.fetch(FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { wp in
                wp.date >= dayStart && wp.date < dayEnd
            }
        ))
        guard let workout = workouts.first else {
            return .abandoned(
                summary: "no WorkoutPlan for the day",
                actionSummary: "swapDayType \(args.newType)"
            )
        }
        let summary = "swapDayType → \(args.newType)"
        if workout.status == .completed {
            return .followedThrough(
                summary: "completed (\(workout.type.rawValue))",
                actionSummary: summary
            )
        }
        if workout.status == .skipped {
            return .abandoned(summary: "workout skipped", actionSummary: summary)
        }
        return .unclear(actionSummary: summary)
    }

    /// Activity-insert grading: look for ANY workout or extra activity
    /// that ran on the day. Without a richer Activity log we treat
    /// "any workout finished" as the proxy.
    @MainActor
    private func gradeInsertActivity(
        payload: Data,
        decisionDate _: Date,
        evaluationDate _: Date
    ) async throws -> OutcomeEvidence {
        guard let args = try? decoder.decode(InsertActivityArgsLite.self, from: payload) else {
            return .unclear(actionSummary: "insertActivity — unparseable payload")
        }
        let context = modelContainer.mainContext
        guard let date = try? CoachToolDispatcherAdapter.parseDate(args.date) else {
            return .unclear(actionSummary: "insertActivity — bad date")
        }
        let dayStart = Calendar.current.startOfDay(for: date)
        guard let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) else {
            return .unclear(actionSummary: "insertActivity — bad date math")
        }
        let workouts = try context.fetch(FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { wp in
                wp.date >= dayStart && wp.date < dayEnd && wp.statusRaw == "completed"
            }
        ))
        let summary = "insertActivity '\(args.name)'"
        if !workouts.isEmpty {
            return .followedThrough(summary: "activity day completed a workout", actionSummary: summary)
        }
        return .abandoned(summary: "no completed activity on the day", actionSummary: summary)
    }

    /// Bedtime-shift grading: pull HK sleep ending on (decisionDate+1),
    /// check whether the inBedStart shifted toward the requested time.
    @MainActor
    private func gradeShiftBedtime(
        payload: Data,
        decisionDate: Date,
        evaluationDate _: Date
    ) async throws -> OutcomeEvidence {
        guard let args = try? decoder.decode(ShiftBedtimeArgs.self, from: payload) else {
            return .unclear(actionSummary: "shiftBedtime — unparseable payload")
        }
        guard let targetDate = try? CoachToolDispatcherAdapter.parseDate(args.date),
              let (targetH, targetM) = try? Self.parseHHmm(args.newBedtimeHHmm)
        else {
            return .unclear(actionSummary: "shiftBedtime — bad inputs")
        }
        let evalDay = Calendar.current.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
        let sleep = try? await sleepReader.sleepEnding(on: evalDay)
        guard let sleep else {
            return .unclear(actionSummary: "shiftBedtime — no HK sleep data")
        }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: sleep.inBedStart)
        let actualH = comps.hour ?? 0
        let actualM = comps.minute ?? 0
        let targetMins = targetH * 60 + targetM
        let actualMins = actualH * 60 + actualM
        // Normalize across midnight — bedtime around 22:00–02:00 wraps.
        // Compute the smaller of the two circular distances.
        let raw = abs(targetMins - actualMins)
        let circularDiff = min(raw, 24 * 60 - raw)

        let summary = "shiftBedtime → \(args.newBedtimeHHmm)"
        let evidence = String(
            format: "actual %02d:%02d, target %02d:%02d, Δ %d min",
            actualH, actualM, targetH, targetM, circularDiff
        )
        if circularDiff <= 30 {
            return OutcomeEvidence(
                outcome: .followedThrough,
                summary: evidence,
                actionSummary: summary
            )
        }
        // Sleep happened but bedtime not near target. Use generic
        // good/bad based on hours.
        if sleep.totalHours >= 7.0 {
            return OutcomeEvidence(
                outcome: .goodSleep,
                summary: evidence + String(format: ", %.1fh", sleep.totalHours),
                actionSummary: summary
            )
        }
        return OutcomeEvidence(
            outcome: .badSleep,
            summary: evidence + String(format: ", %.1fh", sleep.totalHours),
            actionSummary: summary
        )
    }

    // MARK: - Helpers

    private static func parseHHmm(_ raw: String) throws -> (Int, Int) {
        let parts = raw.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0...23).contains(h),
              (0...59).contains(m)
        else {
            throw EvidenceError.malformedTime(raw)
        }
        return (h, m)
    }

    private static func scheduledDate(for meal: PlannedMeal) throws -> Date {
        let (h, m) = try parseHHmm(meal.scheduledTime)
        let dayStart = Calendar.current.startOfDay(for: meal.dayDate)
        guard let date = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: dayStart) else {
            throw EvidenceError.malformedTime(meal.scheduledTime)
        }
        return date
    }
}

// MARK: - Errors

enum EvidenceError: Error, Equatable {
    case malformedTime(String)
}

// MARK: - Lite arg DTOs

/// Lightweight payload decoder for insertActivity. The full args struct
/// in CoachAdapters carries enums that aren't worth dragging here — we
/// only need the name + date to grade.
private struct InsertActivityArgsLite: Decodable, Sendable {
    let name: String
    let date: String
}
