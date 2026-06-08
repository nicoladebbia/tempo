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
        fatigueEWMA: Double? = nil
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.learnedIncrements = learnedIncrements
        self.recoveryThresholdOffset = recoveryThresholdOffset
        self.fatigueEWMA = fatigueEWMA
    }
}
