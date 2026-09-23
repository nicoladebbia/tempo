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
    /// §21.4 two-a-day gates: minimum gap between parts (§12 spacing) and the
    /// ACWR above which a second part is never allowed. [D]
    static let compositeMinGapMin = 6 * 60
    static let acwrCompositeMax: Double = 1.3
    /// Illness triad (2026-06-09): skin-temp deviation vs 30d baseline and
    /// absolute SpO2 floor. Either alone is noise (hydration, sensor drift);
    /// TWO of the triad (resp / skin temp / SpO2) on a non-green day is the
    /// pre-symptomatic illness signature. [D] cutoffs.
    static let skinTempSevereDeltaC: Double = 1.0
    static let spo2SevereFloor: Double = 94

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
        // Route A — composite. Trust Whoop's fused score — when there is one
        // (no sync today ≠ red). [L]
        if p.hasRecoveryScore, p.recoveryScore < recoveryRed { return true }

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

        // Illness TRIAD route (2026-06-09) — any TWO of resp-rate elevation,
        // skin-temp deviation, and low SpO2 on a non-green day. Catches the
        // incubating-illness day the resp-only route misses (e.g. fever-warm
        // skin + low oxygen with normal breathing).
        if p.recoveryScore < recoveryGreen {
            var illnessSignals = 0
            if let rd = p.respDeltaBrMin, rd >= respSevereBrMin { illnessSignals += 1 }
            if let td = p.skinTempDeltaC, td >= skinTempSevereDeltaC { illnessSignals += 1 }
            if let ox = p.spo2, ox < spo2SevereFloor { illnessSignals += 1 }
            if illnessSignals >= 2 { return true }
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

        // §21.4 composite-day gate: a two-part day must respect the interference
        // rules (gap, legs+sprint, ACWR, T-0, hard+hard). Strips the offending
        // LATER part rather than nuking the session. No-op on single-part days.
        let composite = applyCompositeDayRules(matchClamped.session, picture: p)

        switch tier {
        case .severe:
            return FloorDecision(
                tier: .severe,
                session: recoverySession(reason: severeReason(p)),
                wasDowngraded: true,
                reason: severeReason(p)
            )
        case .moderate:
            let clamped = clampIntensity(composite.session, to: .moderate)
            let changed = clamped != session
            return FloorDecision(
                tier: .moderate,
                session: clamped,
                wasDowngraded: changed,
                reason: changed ? "Yellow recovery — intensity capped." : "Yellow recovery — within limits."
            )
        case .normal:
            let changed = matchClamped.changed || composite.changed
            let reason = [matchClamped.reason, composite.reason].first { !$0.isEmpty } ?? ""
            return FloorDecision(
                tier: .normal,
                session: composite.session,
                wasDowngraded: changed,
                reason: changed ? reason : "Clear to train as prescribed."
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
                    scheduledMin: nil,
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
        if p.hasRecoveryScore, p.recoveryScore < recoveryRed { return "Recovery red (\(Int(p.recoveryScore))). Recover today." }
        if let debt = p.sleepDebt, debt >= sleepDebtSevere { return "Sleep debt \(String(format: "%.1f", debt))h. Recover today." }
        if let rd = p.respDeltaBrMin, rd >= respSevereBrMin { return "Respiratory rate elevated — possible illness. Recover." }
        if let td = p.skinTempDeltaC, td >= skinTempSevereDeltaC { return "Skin temp +\(String(format: "%.1f", td))°C vs baseline — possible illness. Recover." }
        if let ox = p.spo2, ox < spo2SevereFloor { return "Blood oxygen \(Int(ox))% — below your normal. Recover." }
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

    // MARK: - Composite-day rules (§21.4 — the two-a-day interference gate)

    /// Enforces the §21.4 rules on a multi-part session by STRIPPING the
    /// offending later part(s), never nuking the whole session — the anchor
    /// (earliest) part always survives. Single-part sessions pass untouched.
    static func applyCompositeDayRules(
        _ s: DailySessionDTO,
        picture p: ReadinessPicture
    ) -> (session: DailySessionDTO, changed: Bool, reason: String) {
        var parts = s.parts
        guard parts.count >= 2 else { return (s, false, "") }
        var reason = ""

        // Match T-0: gym work today is a PRIMER only — no leg loading before
        // kickoff. Drops the offending gym blocks (not the match part).
        if p.daysUntilNextMatch == 0 {
            let cleaned = parts.map { part in
                (part.scheduledMin, part.blocks.filter { !isLegsGymBlock($0) })
            }.filter { !$0.1.isEmpty }
            if !cleaned.isEmpty, cleaned.flatMap(\.1).count != parts.flatMap(\.blocks).count {
                reason = "Match today — leg loading before kickoff dropped."
                parts = cleaned
                if parts.count < 2 {
                    return (rebuild(s, parts: parts), true, reason)
                }
            }
        }

        // Later parts must justify themselves against everything already kept.
        var kept = [parts[0]]
        for part in parts.dropFirst() {
            if let violation = compositeViolation(of: part, against: kept, session: s, picture: p) {
                if reason.isEmpty { reason = violation }
                continue
            }
            kept.append(part)
        }

        let changed = kept.flatMap(\.blocks).count != s.blocks.count
        guard changed else { return (s, false, "") }
        return (rebuild(s, parts: kept), true, reason)
    }

    /// First §21.4 rule the candidate later part breaks, or nil if it's legal.
    private static func compositeViolation(
        of part: (scheduledMin: Int?, blocks: [SessionBlockDTO]),
        against kept: [(scheduledMin: Int?, blocks: [SessionBlockDTO])],
        session s: DailySessionDTO,
        picture p: ReadinessPicture
    ) -> String? {
        // ACWR over the line → no second part, full stop (whole-day budget).
        if let acwr = p.acuteChronicStrainRatio, acwr > acwrCompositeMax {
            return "Training load already high (ACWR \(String(format: "%.1f", acwr))) — second session dropped."
        }

        // §12 spacing: parts < 6h apart. Only verifiable when both are timed.
        if let start = part.scheduledMin,
           let prev = kept.compactMap(\.scheduledMin).max(),
           start - prev < compositeMinGapMin {
            return "Sessions \(String(format: "%.1f", Double(start - prev) / 60))h apart — need ≥6h between parts. Second dropped."
        }

        // Heavy lower-body + field sprint/agility never share a day.
        let isHard = (intensityRank[s.intensity] ?? 0) >= (intensityRank[.hard] ?? 3)
        let keptBlocks = kept.flatMap(\.blocks)
        let legsAnywhere = (keptBlocks + part.blocks).contains(where: isLegsGymBlock)
        let partPairsFieldWithLegs = legsAnywhere
            && (part.blocks.contains { $0.kind == .field } || keptBlocks.contains { $0.kind == .field })
        if isHard, partPairsFieldWithLegs {
            return "Heavy legs + field work in one day — interference. Second session dropped."
        }

        // Hard + hard is illegal: on a hard day the second part must be
        // demonstrably easy (mobility/rest, or every block ≤75% intensity).
        if isHard, !isEasyPart(part.blocks) {
            return "Two hard sessions in one day — second dropped. One hard effort per day."
        }

        return nil
    }

    private static func isLegsGymBlock(_ block: SessionBlockDTO) -> Bool {
        guard block.kind == .gym, let split = block.split?.lowercased() else { return false }
        return split.contains("leg") || split.contains("lower")
    }

    /// Easy enough to ride shotgun on a hard day: recovery-kind blocks, or
    /// explicitly sub-76% intensity on every loaded block.
    private static func isEasyPart(_ blocks: [SessionBlockDTO]) -> Bool {
        blocks.allSatisfy { block in
            block.kind == .mobility || block.kind == .rest
                || (block.intensityPct.map { $0 <= 75 } ?? false)
        }
    }

    /// Rebuilds the session with the surviving parts' blocks, everything else
    /// intact. (durationMin stays as prescribed — it's advisory, and the card
    /// shows the parts that remain.)
    private static func rebuild(
        _ s: DailySessionDTO,
        parts: [(scheduledMin: Int?, blocks: [SessionBlockDTO])]
    ) -> DailySessionDTO {
        DailySessionDTO(
            modality: s.modality,
            intensity: s.intensity,
            durationMin: s.durationMin,
            blocks: parts.flatMap(\.blocks),
            shortWhy: s.shortWhy,
            fullWhy: s.fullWhy,
            expectedStrain: s.expectedStrain,
            expectedSessionRPE: s.expectedSessionRPE
        )
    }
}
