//
// AdaptiveProfile.swift
// Tempo
//
// Phase 3 (TRAINING_INTELLIGENCE_TO_10.md Fix 3.1) — on-device personalization.
// One row per user. Holds the bounded, online-learned signals that turn the
// deterministic engine from "adapts to inputs" into "learns YOU": per-exercise
// increments, a personal recovery-threshold offset, and a fatigue trend.
//
// This is NOT a trained model — it's a set of slow, bounded EWMA/nudge updates
// (see AdaptiveProfileUpdater). Bounded by design: every value is clamped so a
// bad week can never produce an unsafe prescription. The deterministic engine
// remains the floor; the profile only tunes WITHIN the safe envelope.
//

import Foundation
import SwiftData

@Model
final class AdaptiveProfile {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    var updatedAt: Date

    // MARK: - Learned signals

    /// Per-exercise learned weight increment (kg), keyed by `Exercise.id`.
    /// Starts unset → the engine uses the equipment default. Nudged up when the
    /// user repeatedly logs easy clean sessions, down after repeated holds /
    /// failures. Always bounded by AdaptiveProfileUpdater (never runs away).
    var learnedIncrements: [UUID: Double]

    /// Signed offset (points) applied to the user's recovery zone thresholds.
    /// A user who trains well at "yellow" earns a negative offset (green starts
    /// lower for them); one who craters earns positive. CLAMPED to ±10 so a
    /// learned offset can never invert the safety meaning of the red zone.
    var recoveryThresholdOffset: Double

    /// Exponentially-weighted moving average of recent session RPE — the fatigue
    /// trend. A rising EWMA at flat/declining load means accumulating fatigue,
    /// which biases `isDeloadWeek` toward an earlier deload than the fixed cycle.
    /// nil until the first entered-feedback session.
    var fatigueEWMA: Double?

    /// When `fatigueEWMA` last moved (a session with entered RPE). The EWMA
    /// only updates on lifting sessions, so without a clock a fatigue-triggered
    /// full-rest deload — which removes every lifting session — could never
    /// clear. nil on rows created before this field existed.
    var fatigueUpdatedAt: Date?

    /// Neutral effort the fatigue trend relaxes toward while no sessions are
    /// logged (matches the default set RPE of 7).
    static let fatigueBaseline = 7.0
    /// Days for the fatigue excess over baseline to halve during rest.
    static let fatigueHalfLifeDays = 5.0

    /// `fatigueEWMA` relaxed toward baseline by the days since it last moved —
    /// what the deload trigger should read. A week of rest brings even a
    /// maximal 10 back under the trigger, so a fatigue deload self-clears.
    func effectiveFatigueEWMA(asOf now: Date = Date()) -> Double? {
        Self.decayedFatigue(fatigueEWMA, lastUpdated: fatigueUpdatedAt ?? updatedAt, asOf: now)
    }

    nonisolated static func decayedFatigue(_ ewma: Double?, lastUpdated: Date, asOf now: Date) -> Double? {
        guard let ewma else { return nil }
        // Whole days of rest only — sub-day gaps (back-to-back sessions) leave it untouched.
        let days = max(0, (now.timeIntervalSince(lastUpdated) / 86_400).rounded(.down))
        let excess = ewma - fatigueBaseline
        return fatigueBaseline + excess * pow(0.5, days / fatigueHalfLifeDays)
    }

    /// Exercise substitutions the user taught us by swapping: source
    /// `Exercise.id` → the replacement they actually do (e.g. cable pushdown
    /// → the pushdown machine they use). Plan generation prescribes the
    /// replacement from then on; its own logged history drives its weights.
    /// Single-hop (chain-collapsed on write, never resolved recursively).
    /// Inline default → migration-safe on existing rows.
    var preferredSwaps: [UUID: UUID] = [:]

    // MARK: - Persisted run-once guards

    //
    // These MUST be persisted, not in-memory on the VM: the VM is rebuilt on
    // every cold start, so an in-memory guard would let the once-per-week /
    // once-per-day work re-run every app launch. For the Phase-4 outcome review
    // that means applyOutcome would COMPOUND (×1.05 or ×0.9 per launch) against
    // the persisted profile — a real drift bug. Persisting the keys makes the
    // guards survive relaunch, which also hardens the AI cost caps.

    /// ISO week-start day (yyyy-MM-dd) the weekly outcome review last ran for.
    var lastOutcomeReviewWeekKey: String?

    /// ISO week-start day the AI program hydration last ran for (≤1 Sonnet/week).
    var lastAIHydratedWeekKey: String?

    /// ISO day the live recovery-adjustment check last ran for (≤1 Haiku/day).
    var lastAdjustmentCheckedDayKey: String?

    /// ISO day the daily readiness brain (DailyReadinessCoach) last ran for
    /// (≤1 Haiku/day — the D2 daily-session call). INTELLIGENT_TRAINING_SYSTEM §5.1.
    var lastDailySessionDayKey: String?

    // MARK: - Bounds (single source of truth, shared with the updater + tests)

    static let maxThresholdOffset: Double = 10
    static let minThresholdOffset: Double = -10

    // MARK: - Accessors

    /// The learned increment for an exercise, or nil to fall back to the
    /// equipment default in the engine.
    func learnedIncrement(for exerciseID: UUID) -> Double? {
        learnedIncrements[exerciseID]
    }

    /// The offset clamped to the safe band — always read through this, never the
    /// raw stored value, so a corrupted/migrated row can't escape the envelope.
    var clampedThresholdOffset: Double {
        min(max(recoveryThresholdOffset, Self.minThresholdOffset), Self.maxThresholdOffset)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        updatedAt: Date = Date(),
        learnedIncrements: [UUID: Double] = [:],
        recoveryThresholdOffset: Double = 0,
        fatigueEWMA: Double? = nil,
        lastOutcomeReviewWeekKey: String? = nil,
        lastAIHydratedWeekKey: String? = nil,
        lastAdjustmentCheckedDayKey: String? = nil
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.learnedIncrements = learnedIncrements
        self.recoveryThresholdOffset = recoveryThresholdOffset
        self.fatigueEWMA = fatigueEWMA
        self.lastOutcomeReviewWeekKey = lastOutcomeReviewWeekKey
        self.lastAIHydratedWeekKey = lastAIHydratedWeekKey
        self.lastAdjustmentCheckedDayKey = lastAdjustmentCheckedDayKey
    }
}
