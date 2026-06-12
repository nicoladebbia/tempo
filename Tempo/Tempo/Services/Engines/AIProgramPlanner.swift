//
// AIProgramPlanner.swift
// Tempo
//
// Phase 2 (TRAINING_INTELLIGENCE_TO_10.md Fix 2.3) — the LLM↔engine
// reconciliation layer. Calls the backend TrainingProgramService (Sonnet) for
// a weekly skeleton, then RECONCILES the proposal against the deterministic
// week plan. The deterministic plan is the safety floor and always wins on
// safety: the AI may tune volume within bounds, but it can never violate the
// football T-0/T-1/T+1 rules, turn a recovery-mandated rest/mobility day into
// training, or push volume outside a clamped band.
//
// "LLM proposes, engine disposes."
//

import Foundation

@MainActor
final class AIProgramPlanner {
    private let api: APIClient

    // MARK: - Reconcile clamps (the safety envelope)

    /// AI-proposed per-day volume is clamped to this band. The floor already
    /// applied recovery cuts; the AI can fine-tune within a conservative range
    /// but never exceed +10% (overreach risk) or drop below 50% (that's a
    /// deterministic rest/mobility decision, not a volume tweak).
    nonisolated static let minVolume: Double = 0.5
    nonisolated static let maxVolume: Double = 1.1

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Plan

    /// Fetch an AI weekly skeleton and reconcile it against the deterministic
    /// floor. On ANY failure (network down, 402 not-Pro/no-consent, malformed
    /// response, empty days) returns the deterministic plan unchanged — the AI
    /// path is strictly an upgrade, never a hard dependency.
    ///
    /// Returns the reconciled plans plus the AI rationale (nil when the floor
    /// was used) so the UI can show "why" when — and only when — AI ran.
    func planWeek(
        deterministicPlans: [WorkoutPlan],
        weekStart: Date,
        recovery7Day: [Int],
        recentSessions: [String],
        footballDays: [String],
        goal: String
    ) async -> (plans: [WorkoutPlan], rationale: String?) {
        let request = DayPlanTrainingProgramRequest(
            weekStart: Self.isoDay(weekStart),
            footballDays: footballDays,
            recentRecovery7Day: recovery7Day,
            recentSessions: recentSessions,
            goal: goal
        )

        let response: DayPlanTrainingProgramResponse
        do {
            response = try await api.request(
                APIEndpoint<DayPlanTrainingProgramResponse>.dayPlanTrainingProgram(),
                body: request
            )
        } catch {
            #if DEBUG
                print("\(DebugTrace.prefix)[training_ai] program fetch failed — using deterministic floor: \(error)")
            #endif
            return (deterministicPlans, nil)
        }

        guard let days = response.days, !days.isEmpty else {
            // Backend produced rationale only (or hydration-shaped response).
            // Nothing to reconcile against → floor stands.
            return (deterministicPlans, nil)
        }

        let reconciled = Self.reconcile(ai: days, floor: deterministicPlans)
        #if DEBUG
            print("\(DebugTrace.prefix)[training_ai] program reconciled \(reconciled.count) days against floor")
        #endif
        return (reconciled, response.rationale)
    }

    // MARK: - Reconcile (pure, unit-tested — the safety core)

    /// Merge the AI proposal into the deterministic floor under hard safety
    /// rules. Pure and `nonisolated static` so it's testable with no network,
    /// no VM, no device. Matching is by weekday; an AI day with no floor match
    /// is ignored (the floor defines which days exist).
    ///
    /// Rules (floor wins on every one):
    /// 1. The floor's workout TYPE is authoritative. Recovery-mandated `.rest`
    ///    / `.mobility`, match-day `.football`, and the T-1 leg-swap are safety
    ///    / fixture decisions — the AI can never change them.
    /// 2. The AI may only adjust `recoveryAdjustment` (volume), and only on days
    ///    the floor left as actual training, clamped to [minVolume, maxVolume]
    ///    AND never ABOVE the floor's own value (AI can trim, not inflate, a
    ///    recovery-reduced day).
    /// 3. Everything else (date, status, id, exercises) is preserved from the
    ///    floor object — we mutate volume + note in place, nothing structural.
    nonisolated static func reconcile(
        ai: [TrainingProgramDayDTO],
        floor: [WorkoutPlan]
    ) -> [WorkoutPlan] {
        let cal = Calendar.current
        // Index AI proposals by lowercased weekday name.
        let aiByDay = Dictionary(
            ai.map { ($0.day.lowercased(), $0) }
        ) { first, _ in first }

        for plan in floor {
            let weekdayName = Self.weekdayName(for: plan.date, cal: cal)
            guard let proposal = aiByDay[weekdayName] else { continue }

            // Rule 1 — TYPE is the floor's. A non-training floor day is never
            // overridden into training, regardless of what the AI proposed.
            guard Self.isTrainingType(plan.type) else { continue }

            // Rule 2 — volume only, clamped, and never inflated above the floor.
            let proposed = proposal.volumeAdjustment
            let clamped = min(max(proposed, minVolume), maxVolume)
            let safe = min(clamped, plan.recoveryAdjustment)
            if abs(safe - plan.recoveryAdjustment) > 0.001 {
                plan.recoveryAdjustment = safe
                plan.notes = "AI-tuned volume (recovery trend)"
            }
        }
        return floor
    }

    // MARK: - Helpers

    /// Training types the AI is allowed to fine-tune. Rest / mobility / football
    /// are excluded — those are deterministic safety / fixture decisions.
    nonisolated static func isTrainingType(_ type: WorkoutType) -> Bool {
        switch type {
        case .push, .pull, .legs, .upper, .lower, .fullBody,
             .run, .sprint, .conditioning, .pool:
            true
        case .football, .mobility, .rest:
            false
        }
    }

    nonisolated static func weekdayName(for date: Date, cal: Calendar) -> String {
        let weekday = cal.component(.weekday, from: date) // 1 = Sunday
        let names = ["sunday", "monday", "tuesday", "wednesday",
                     "thursday", "friday", "saturday"]
        return names[(weekday - 1) % 7]
    }

    /// Convert the weekday-flag `ActiveDays` into the lowercase day-name list
    /// the backend program prompt expects (e.g. ["saturday"]). Uses
    /// `isActive(on:)` with Foundation weekday numbers (1 = Sunday).
    nonisolated static func footballDayNames(_ days: ActiveDays) -> [String] {
        // Foundation weekday: 1=Sun … 7=Sat. Map to lowercase names.
        let mapping: [(weekday: Int, name: String)] = [
            (1, "sunday"), (2, "monday"), (3, "tuesday"), (4, "wednesday"),
            (5, "thursday"), (6, "friday"), (7, "saturday"),
        ]
        return mapping.filter { days.isActive(on: $0.weekday) }.map(\.name)
    }

    nonisolated static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
