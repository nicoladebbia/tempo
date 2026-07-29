//
// PrescriptionMath.swift
// Tempo
//
// §11.12 — the set-level prescription brain, pure and unit-tested.
//
// Anchors every working prescription to the lift's CURRENT estimated 1RM
// (recency-decayed rolling max) instead of last-session weight + increment:
//
//   weight for (reps @ RIR) = e1RM / (1 + (reps + RIR) / 30)     [reverse Epley]
//
// A set of 5 at RIR 2 is a 7-rep-max load — the same formula the e1RM
// estimate itself uses, run backwards, so prescriptions and history speak
// one language. Roles inside a session train different qualities
// (heavy primary compound / building secondaries / pump isolations), and a
// second same-type day in one week undulates to a volume scheme (DUP) so
// upper/lower and full-body splits don't grind the same intensity twice.
// A lift whose rolling e1RM has stalled gets a wave reset (-8%) to rebuild
// momentum instead of banging against the same ceiling.
//

import Foundation

enum PrescriptionMath {
    // MARK: - Inputs

    struct HistorySample {
        let date: Date
        let e1RM: Double?
    }

    /// The exercise's job within one session.
    enum Role {
        case primaryCompound
        case secondaryCompound
        case isolation
    }

    /// One prescription scheme: rep target, effort target, display zone.
    struct Scheme: Equatable {
        let reps: Int
        let rir: Int
        /// UI tag: HEAVY / BUILD / PUMP.
        let zoneLabel: String
    }

    // MARK: - Tuning constants

    /// Recency decay per day of age on a history e1RM — an 85 kg session
    /// three weeks ago outranks a stale 90 from three months back.
    static let dailyDecay = 0.995
    /// History window considered for the rolling e1RM.
    static let windowDays = 60
    /// Minimum scored sessions before the e1RM path takes over from the
    /// legacy increment engine.
    static let minSamples = 2
    /// Wave reset applied to a plateaued lift's anchor.
    static let plateauResetFactor = 0.92

    // MARK: - Core math

    /// Reverse Epley: the load that allows `reps` with `rir` still in the
    /// tank, given a 1-rep max. (reps + rir) is the implied rep max.
    static func weight(e1RM: Double, reps: Int, rir: Int) -> Double {
        guard e1RM > 0, reps > 0, rir >= 0 else {
            return 0
        }
        return e1RM / (1 + Double(reps + rir) / 30.0)
    }

    /// Rolling e1RM: recency-decayed max over the trailing window.
    /// nil until `minSamples` scored sessions exist — callers fall back to
    /// the legacy progression engine.
    static func currentE1RM(samples: [HistorySample], now: Date = Date()) -> Double? {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let scored = samples.compactMap { sample -> Double? in
            guard sample.date >= cutoff, sample.date <= now,
                  let e1RM = sample.e1RM, e1RM > 0
            else {
                return nil
            }
            let ageDays = max(0, now.timeIntervalSince(sample.date) / 86_400)
            return e1RM * pow(dailyDecay, ageDays)
        }
        guard scored.count >= minSamples else {
            return nil
        }
        return scored.max()
    }

    /// Session scheme by role and week occurrence (0 = first same-type day
    /// this week). Occurrence ≥1 undulates to a volume day — classic DUP.
    static func scheme(role: Role, weekOccurrence: Int) -> Scheme {
        if weekOccurrence == 0 {
            switch role {
            case .primaryCompound: return Scheme(reps: 5, rir: 2, zoneLabel: "HEAVY")
            case .secondaryCompound: return Scheme(reps: 8, rir: 2, zoneLabel: "BUILD")
            case .isolation: return Scheme(reps: 12, rir: 1, zoneLabel: "PUMP")
            }
        }
        switch role {
        case .primaryCompound: return Scheme(reps: 8, rir: 2, zoneLabel: "BUILD")
        case .secondaryCompound: return Scheme(reps: 10, rir: 2, zoneLabel: "BUILD")
        case .isolation: return Scheme(reps: 15, rir: 1, zoneLabel: "PUMP")
        }
    }

    /// Plateau: the best RAW e1RM of the most recent `sessionWindow` scored
    /// sessions shows no gain (>0.5%) over the best of the `sessionWindow`
    /// before it. Needs both windows full — young lifts never read plateaued.
    static func isPlateaued(samples: [HistorySample], sessionWindow: Int = 4) -> Bool {
        let scored = samples
            .filter { ($0.e1RM ?? 0) > 0 }
            .sorted { $0.date < $1.date }
        guard scored.count >= sessionWindow * 2 else {
            return false
        }
        let recent = scored.suffix(sessionWindow).compactMap(\.e1RM).max() ?? 0
        let earlier = scored.dropLast(sessionWindow).suffix(sessionWindow).compactMap(\.e1RM).max() ?? 0
        guard earlier > 0 else {
            return false
        }
        return recent <= earlier * 1.005
    }

    /// Display zone recovered from a persisted rep target (zone itself is
    /// not stored) — 5→HEAVY, 8/10→BUILD, 12+→PUMP.
    static func zoneLabel(forReps reps: Int) -> String {
        switch reps {
        case ..<7: "HEAVY"
        case ..<12: "BUILD"
        default: "PUMP"
        }
    }
}
