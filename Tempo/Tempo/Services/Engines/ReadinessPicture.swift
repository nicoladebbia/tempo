//
// ReadinessPicture.swift
// Tempo
//
// The full-body-state value type the daily training brain reasons over
// (docs/INTELLIGENT_TRAINING_SYSTEM.md §4.1). Pure value type — no SwiftData,
// no network. It carries today's raw Whoop signals + the COMPUTED trends that
// are "the missing intelligence" (HRV-vs-baseline, RHR-vs-baseline, acute:chronic
// strain), plus the cold-start sample counts the safety floor gates on.
//
// D0 scope: this is the SHAPE the prompt harness feeds Haiku. The trend fields
// are plain stored properties here — they are hand-authored by the harness's
// synthetic fixtures. The derivation-from-30-day-history (ReadinessTrendMath /
// ReadinessAssembler) is D1; keeping it out of D0 keeps a harness FAIL
// attributable to the PROMPT, not to trend math.
//

import Foundation

// MARK: - ReadinessPicture

/// One day's assembled body-state picture. Value semantics; deterministic.
struct ReadinessPicture: Equatable, Sendable {

    // MARK: Today's raw signals (from DailyRecovery)

    /// Whoop's fused recovery score, 0–100. The composite Route-A signal.
    let recoveryScore: Double
    /// Today's HRV (rMSSD, ms). nil when not synced.
    let hrv: Double?
    /// Today's resting HR (bpm). nil when not synced.
    let rhr: Double?
    /// Today's respiratory rate (breaths/min). nil when not synced.
    let respRate: Double?
    /// Total sleep last night (hours). nil when not synced.
    let sleepHours: Double?
    /// Whoop sleep debt (hours). The existing `DailyRecovery.sleepDebt` field;
    /// `>= 4.0` is the in-code critical convention (§6.1 [L] reuse).
    let sleepDebt: Double?
    /// Whole-day strain (Whoop). The `DailyRecovery.strain` field — NB: NOT
    /// `dayStrain` (§2 correction). nil when not synced.
    let dayStrain: Double?
    /// Deep sleep minutes last night. nil when not synced.
    let deepSleepMin: Int?

    // MARK: Computed trends (THE missing intelligence — synthetic in D0, derived in D1)

    /// z-score of the trailing-7-day mean of ln(rMSSD) vs the trailing-30-day
    /// baseline (mean/SD of ln(rMSSD)). Negative = HRV suppressed. nil when the
    /// baseline can't be computed (< minBaselineSamples valid days). §6.1 [L].
    let hrvZScore: Double?
    /// 7-day trend direction of HRV, for the prompt's human-readable line.
    let hrvTrend7d: TrendDirection
    /// RHR today minus the trailing-30-day baseline mean, in bpm (the primary,
    /// intuitive deviation). Positive = elevated. nil when no baseline. §6.1 [D].
    let rhrDeltaBpm: Double?
    /// z-score backstop for RHR (normal-distributed → raw z is fine). nil when no baseline.
    let rhrZScore: Double?
    /// Respiratory rate today minus 30-day baseline, br/min. Positive = elevated
    /// (Whoop's documented illness tell). nil when no baseline. §6.1.
    let respDeltaBrMin: Double?
    /// Acute:chronic whole-day-strain ratio (7-day load vs 28-day, EWMA-decoupled
    /// form per §12 G4). > ~1.3 = overreach flag. nil when insufficient history.
    let acuteChronicStrainRatio: Double?

    // MARK: Yesterday's actual work (from WhoopWorkout → ActivitySession, surfaced not ignored)

    let yesterdaySessions: [YesterdaySession]

    // MARK: Body composition (Withings → HealthKit)

    let weightKg: Double?
    let bodyFatPct: Double?
    let leanMassKg: Double?

    // MARK: Subjective (morning check-in — one-way downgrade, §15.5)

    let checkIn: MorningCheckInSnapshot?

    // MARK: Schedule

    /// Days until the next logged match (0 = today, 1 = tomorrow = T-1). nil = none scheduled.
    let daysUntilNextMatch: Int?

    /// The declared training-block emphasis in force today (§14 Decision 1).
    /// nil = no block ever set → the prompt states "physique (default)" and the
    /// weekly goal stays the pre-D3 "hypertrophy" literal. Defaulted so the
    /// memberwise init keeps pre-D3 construction sites compiling unchanged.
    var blockEmphasis: BlockEmphasis? = nil

    /// Today's venue context (§16): the user's confirmed answer when present,
    /// else the learned weekday pattern (≥3 samples). nil = nothing to say —
    /// the prompt stays silent rather than guessing (§16.3 honesty).
    var venueToday: VenueTodaySnapshot? = nil

    // MARK: Cold-start accounting (the gate protecting every raw route — §6.3, §14.2)

    /// Count of valid (non-nil) HRV/RHR samples in the trailing 30 days. Drives
    /// the floor's ≥14-sample gate; below it, Routes B/resp/RHR-deviation disable
    /// and the floor degrades to Route A (recovery zone) + absolute sleep only.
    let validBaselineSampleCount: Int
    /// Days of DailyRecovery history accrued. Drives the BRAIN's ≥30-day gate
    /// (trend-reasoning withheld until then). Intentionally distinct from the
    /// floor's 14 — safety engages earlier than sophistication (§14.2).
    let historyDayCount: Int

    // MARK: Cold-start thresholds (named constants — §14.1)

    /// Floor may use z-score routes once it has at least this many valid samples.
    static let minBaselineSamples = 14
    /// Brain withholds trend-based reasoning until at least this many days accrue.
    static let minBrainHistoryDays = 30

    // MARK: Derived helpers

    /// True when the floor's raw multi-signal routes (B / resp / RHR-deviation)
    /// have enough data to fire. Below this the floor is Route-A + sleep only.
    var hasBaselineForFloor: Bool { validBaselineSampleCount >= Self.minBaselineSamples }

    /// True when the brain may feed trend-based reasoning to Claude. Before this,
    /// SIMPLE mode: deterministic engine + recovery-score-only, trends "building".
    var hasBaselineForBrain: Bool { historyDayCount >= Self.minBrainHistoryDays }
}

// MARK: - VenueTodaySnapshot

/// Venue context for today's prompt (§16). `confirmed` = the user answered the
/// morning proposal; otherwise it's the learned pattern, and `assertsTime`
/// carries the §16.3 confidence tier (≥5 samples may assert "usual 4PM").
struct VenueTodaySnapshot: Equatable, Sendable {
    let venueRaw: String
    let startMin: Int?
    let durationMin: Int?
    let confirmed: Bool
    let assertsTime: Bool
}

// MARK: - TrendDirection

enum TrendDirection: String, Codable, Sendable {
    case rising
    case flat
    case falling
}

// MARK: - YesterdaySession

/// One Whoop-detected activity from yesterday, surfaced into today's picture.
struct YesterdaySession: Equatable, Sendable, Codable {
    let type: String
    let strain: Double?
    let durationMin: Double?
    let avgHR: Double?
}

// MARK: - MorningCheckInSnapshot

/// Value snapshot of the subjective morning check-in (the @Model is D1). All
/// optional — the check-in is dismissible and can DOWNGRADE but never upgrade.
struct MorningCheckInSnapshot: Equatable, Sendable, Codable {
    /// 1–5 (low→high). nil = not answered.
    let mood: Int?
    /// 1–10 perceived stress. nil = not answered.
    let stress: Int?
    /// bodyPart → 1–10 soreness. Empty = none reported.
    let soreness: [String: Int]
    /// Any body part flagged painful (routes away from loading it — §15.5).
    var painFlags: [String] { soreness.filter { $0.value >= 8 }.map(\.key) }
}
