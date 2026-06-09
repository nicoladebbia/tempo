//
// TrainingSafetyFloor.swift
// Tempo
//
// The deterministic veto under the full-Claude daily brain (docs/INTELLIGENT_TRAINING_SYSTEM.md §6).
// Body-data-wins (Decision #3): Claude owns modality/intensity/voice; the floor
// owns "not on a clearly-cooked day." Pure + fully unit-testable: takes the
// Claude DailySessionDTO + the ReadinessPicture, returns a possibly-downgraded
// session and the tier that drove it.
//
// Tiering is a PURE FUNCTION OF ORDERED GATES (§6.2): evaluate every SEVERE
// trigger; if none, evaluate MODERATE; else NORMAL. Cold-start (§6.3): the raw
// multi-signal routes need ≥14 valid samples (ReadinessPicture.minBaselineSamples);
// below that the floor degrades to Route A (recovery zone) + absolute sleep only.
//

import Foundation

// MARK: - FloorTier

enum FloorTier: String, Sendable, Equatable {
    /// Objective markers scream rest. Force recovery/mobility/rest; no override.
    case severe
    /// Yellow recovery + a moderate flag. Allow the modality; clamp load.
    case moderate
    /// Green + no flags. Claude's prescription passes through unchanged.
    case normal
}

// MARK: - FloorDecision

struct FloorDecision: Sendable, Equatable {
    let tier: FloorTier
    /// The (possibly downgraded) session to actually run.
    let session: DailySessionDTO
    /// True when the floor changed Claude's session.
    let wasDowngraded: Bool
    /// Human-readable reason (for the card "why" + debug logs).
    let reason: String
}

// MARK: - TrainingSafetyFloor

enum TrainingSafetyFloor {

    // MARK: Thresholds (§6.1/§6.2 — [L] literature-locked, [D] defensible default)

    /// Recovery band cutoffs (canonical Whoop / in-code RecoveryZone). [L]
    static let recoveryRed: Double = 34
    static let recoveryGreen: Double = 67
    /// HRV z-score (ln-rMSSD, 7d vs 30d). method [L], cutoff [D].
    static let hrvSevereZ: Double = -1.5
    static let hrvModerateZ: Double = -1.0
    /// RHR deviation, bpm above 30-day baseline. [D]
    static let rhrSevereBpm: Double = 5
    static let rhrModerateBpmLow: Double = 3
    static let rhrZBackstop: Double = 1.5
    /// Respiratory rate deviation, br/min above baseline. signal [L], cutoff [D].
    static let respSevereBrMin: Double = 2
    static let respModerateBrMin: Double = 1
    /// Sleep debt (existing `isSleepDebtCritical` convention). [L] reuse.
    static let sleepDebtSevere: Double = 4
    static let sleepDebtModerateLow: Double = 2

    // MARK: - Classification

    /// Ordered-gate tier classification. Pure function of the picture (§6.2).
    static func classifyFloorTier(_ p: ReadinessPicture) -> FloorTier {
        if isSevere(p) { return .severe }
        if isModerate(p) { return .moderate }
        return .normal
    }

    /// SEVERE = ANY of the routes (logical OR). The raw routes (B / resp / RHR)
    /// only fire when the baseline is established (§6.3 cold-start gate).
    static func isSevere(_ p: ReadinessPicture) -> Bool {
        // Route A — composite. Always available; trust Whoop's fused score. [L]
        if p.recoveryScore < recoveryRed { return true }

        // Sleep route — high debt on an already-suppressed (non-green) recovery. [D]
        if let debt = p.sleepDebt, debt >= sleepDebtSevere, p.recoveryScore < recoveryGreen {
            return true
        }

        // The raw multi-signal routes require an established baseline.
        guard p.hasBaselineForFloor else { return false }

        // Route B — raw AND-gate: HRV crash AND RHR spike. [D] cutoffs.
        if let z = p.hrvZScore, z <= hrvSevereZ, rhrFlag(p) {
            return true
        }

        // Illness route — elevated resp rate AND recovery not green. [D] cutoff.
        if let rd = p.respDeltaBrMin, rd >= respSevereBrMin, p.recoveryScore < recoveryGreen {
            return true
        }

        return false
    }

    /// MODERATE = NOT severe, recovery yellow, with ≥1 moderate flag.
    static func isModerate(_ p: ReadinessPicture) -> Bool {
        guard p.recoveryScore >= recoveryRed, p.recoveryScore < recoveryGreen else { return false }

        // Sleep-debt moderate flag is available without a baseline.
        if let debt = p.sleepDebt, debt >= sleepDebtModerateLow, debt < sleepDebtSevere { return true }

        guard p.hasBaselineForFloor else {
            // Cold-start: only Route A (yellow) + sleep. Yellow alone is moderate
            // only if a sleep flag is present; bare yellow with no flag = NORMAL-ish
            // but we keep the conservative "yellow = clamp" stance.
            return true
        }

        if let z = p.hrvZScore, z <= hrvModerateZ { return true }
        if let d = p.rhrDeltaBpm, d >= rhrModerateBpmLow, d < rhrSevereBpm { return true }
        if let rd = p.respDeltaBrMin, rd >= respModerateBrMin { return true }
        return true // yellow recovery itself warrants a clamp (conservative)
    }

    /// RHR is elevated past the severe bpm cutoff OR its z backstop fires.
    private static func rhrFlag(_ p: ReadinessPicture) -> Bool {
        if let d = p.rhrDeltaBpm, d >= rhrSevereBpm { return true }
        if let z = p.rhrZScore, z >= rhrZBackstop { return true }
        return false
    }

    // MARK: - Apply (downgrade)

    /// Applies the floor to Claude's session. SEVERE → force recovery/rest;
    /// MODERATE → clamp intensity to at most `.moderate`; NORMAL → pass through.
    /// Match-protection (T-1) is a SEPARATE schedule-driven gate applied here too.
    static func apply(_ session: DailySessionDTO, picture p: ReadinessPicture) -> FloorDecision {
        let tier = classifyFloorTier(p)

        // Schedule gate first: T-1 to a match → no heavy legs / hard lower-body
        // load regardless of body tier (the existing rule, extended — §6.4/§12).
        let matchClamped = applyMatchProtection(session, picture: p)

        switch tier {
        case .severe:
            return FloorDecision(
                tier: .severe,
                session: recoverySession(reason: severeReason(p)),
                wasDowngraded: true,
                reason: severeReason(p)
            )
        case .moderate:
            let clamped = clampIntensity(matchClamped.session, to: .moderate)
            let changed = clamped != session
            return FloorDecision(
                tier: .moderate,
                session: clamped,
                wasDowngraded: changed,
                reason: changed ? "Yellow recovery — intensity capped." : "Yellow recovery — within limits."
            )
        case .normal:
            return FloorDecision(
                tier: .normal,
                session: matchClamped.session,
                wasDowngraded: matchClamped.changed,
                reason: matchClamped.changed ? matchClamped.reason : "Clear to train as prescribed."
            )
        }
    }

    // MARK: - Helpers

    private static let intensityRank: [SessionIntensity: Int] = [
        .recovery: 0, .easy: 1, .moderate: 2, .hard: 3, .max: 4,
    ]

    /// Caps a session's intensity at `cap`, leaving everything else intact.
    static func clampIntensity(_ s: DailySessionDTO, to cap: SessionIntensity) -> DailySessionDTO {
        guard let cur = intensityRank[s.intensity], let capR = intensityRank[cap], cur > capR else {
            return s
        }
        return DailySessionDTO(
            modality: s.modality,
            intensity: cap,
            durationMin: s.durationMin,
            blocks: s.blocks,
            shortWhy: s.shortWhy,
            fullWhy: s.fullWhy,
            expectedStrain: s.expectedStrain,
            expectedSessionRPE: s.expectedSessionRPE
        )
    }

    /// The deterministic recovery prescription the floor forces on a SEVERE day.
    static func recoverySession(reason: String) -> DailySessionDTO {
        DailySessionDTO(
            modality: "rest",
            intensity: .recovery,
            durationMin: 20,
            blocks: [
                SessionBlockDTO(
                    kind: .mobility,
                    label: "Mobility + easy movement",
                    notes: "Body markers say recover. Light only.",
                    cue: "Move easy, breathe, no load.",
                    split: nil, reps: nil, distanceM: nil, restSec: nil,
                    intensityPct: nil, durationSec: nil, stroke: nil,
                    runType: nil, paceSecPerKm: nil, sets: nil
                ),
            ],
            shortWhy: reason,
            fullWhy: "Objective recovery markers are in the danger zone. Training hard today risks injury or illness — recovery is the prescription. Body data wins.",
            expectedStrain: nil,
            expectedSessionRPE: 2
        )
    }

    private static func severeReason(_ p: ReadinessPicture) -> String {
        if p.recoveryScore < recoveryRed { return "Recovery red (\(Int(p.recoveryScore))). Recover today." }
        if let debt = p.sleepDebt, debt >= sleepDebtSevere { return "Sleep debt \(String(format: "%.1f", debt))h. Recover today." }
        if let rd = p.respDeltaBrMin, rd >= respSevereBrMin { return "Respiratory rate elevated — possible illness. Recover." }
        return "Body markers crashed. Recover today."
    }

    // MARK: - Match protection (separate schedule-driven gate)

    private static func applyMatchProtection(
        _ s: DailySessionDTO,
        picture p: ReadinessPicture
    ) -> (session: DailySessionDTO, changed: Bool, reason: String) {
        // T-1 (match tomorrow): no heavy lower-body load. The existing rule swaps
        // ANY legs day; here we clamp a hard/max lower-body session down.
        guard let d = p.daysUntilNextMatch, d == 1 else {
            return (s, false, "")
        }
        let loadsLegs = s.blocks.contains { block in
            (block.split?.lowercased().contains("leg") ?? false)
                || (block.split?.lowercased().contains("lower") ?? false)
        }
        let isHard = (intensityRank[s.intensity] ?? 0) >= (intensityRank[.hard] ?? 3)
        guard loadsLegs, isHard else { return (s, false, "") }
        let clamped = clampIntensity(s, to: .easy)
        return (clamped, true, "Match tomorrow — legs kept light (T-1 protection).")
    }
}
