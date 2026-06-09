//
// SyntheticPictures.swift
// Tempo
//
// The ~20 synthetic ReadinessPictures the D0 harness feeds Haiku (§5.2-FIX, §19.1).
// Each fixture carries:
//   • a hand-authored ReadinessPicture (trend fields set directly — D0 doesn't
//     derive them; that's D1),
//   • `rawIsSensible`: judges Haiku's RAW session BEFORE the floor — the real
//     prompt-quality signal (a session the floor must rescue is a prompt failure),
//   • an optional `antiPattern`: a named check the floor CANNOT catch
//     (severe→Haiku picks rest unaided; pre-match→no hard legs).
//
// #if DEBUG only.
//

#if DEBUG
import Foundation

struct SyntheticFixture {
    let name: String
    let picture: ReadinessPicture
    /// Judges the RAW Haiku session (pre-floor). True = prompt produced something sensible.
    let rawIsSensible: (DailySessionDTO) -> Bool
    /// Optional named anti-pattern the floor can't catch. nil = no extra check.
    let antiPattern: ((DailySessionDTO) -> Bool)?
    /// Human-readable reason a session was judged not-sensible (for failure notes).
    let diagnose: (DailySessionDTO) -> String

    init(
        _ name: String,
        _ picture: ReadinessPicture,
        rawIsSensible: @escaping (DailySessionDTO) -> Bool,
        antiPattern: ((DailySessionDTO) -> Bool)? = nil,
        diagnose: @escaping (DailySessionDTO) -> String = { "intensity=\($0.intensity.rawValue) modality=\($0.modality)" }
    ) {
        self.name = name
        self.picture = picture
        self.rawIsSensible = rawIsSensible
        self.antiPattern = antiPattern
        self.diagnose = diagnose
    }
}

enum SyntheticPictures {

    // MARK: - Builder

    private static func pic(
        recovery: Double,
        hrvZ: Double? = 0, rhrDelta: Double? = 0, rhrZ: Double? = 0,
        respDelta: Double? = 0, sleepDebt: Double? = 0, acwr: Double? = 1.0,
        yesterday: [YesterdaySession] = [],
        checkIn: MorningCheckInSnapshot? = nil,
        match: Int? = nil,
        validSamples: Int = 30, historyDays: Int = 30
    ) -> ReadinessPicture {
        ReadinessPicture(
            recoveryScore: recovery, hrv: 55, rhr: 50, respRate: 14, sleepHours: 7.5,
            sleepDebt: sleepDebt, dayStrain: 11, deepSleepMin: 85,
            hrvZScore: hrvZ, hrvTrend7d: (hrvZ ?? 0) < -0.5 ? .falling : .flat,
            rhrDeltaBpm: rhrDelta, rhrZScore: rhrZ, respDeltaBrMin: respDelta,
            acuteChronicStrainRatio: acwr, yesterdaySessions: yesterday,
            weightKg: 80, bodyFatPct: 12, leanMassKg: 68, checkIn: checkIn,
            daysUntilNextMatch: match, validBaselineSampleCount: validSamples,
            historyDayCount: historyDays
        )
    }

    // Sensibility helpers — internal (not private) so the calibration test can
    // feed the prompt's own exemplars through them and prove they're not broken.
    static func isRecoveryish(_ s: DailySessionDTO) -> Bool {
        s.intensity == .recovery || s.intensity == .easy ||
            s.modality == "rest" || s.modality == "mobility" ||
            s.blocks.allSatisfy { $0.kind == .mobility || $0.kind == .rest }
    }
    static func notHardLegs(_ s: DailySessionDTO) -> Bool {
        let rank: [SessionIntensity: Int] = [.recovery: 0, .easy: 1, .moderate: 2, .hard: 3, .max: 4]
        let hard = (rank[s.intensity] ?? 0) >= 3
        let legs = s.blocks.contains { ($0.split?.lowercased().contains("leg") ?? false) || ($0.split?.lowercased().contains("lower") ?? false) }
        return !(hard && legs)
    }
    static func noGymWeights(_ s: DailySessionDTO) -> Bool {
        // The gym block must be a pointer: no per-set/weight fields leak in.
        s.blocks.filter { $0.kind == .gym }.allSatisfy { $0.sets == nil }
    }

    // MARK: - The fixtures (~20)

    static var all: [SyntheticFixture] {
        [
            // — Green / normal days: should train, sensible intensity, gym = pointer —
            SyntheticFixture("green-fresh", pic(recovery: 82),
                rawIsSensible: { $0.intensity != .recovery && noGymWeights($0) }),
            SyntheticFixture("green-rested-physique", pic(recovery: 90, hrvZ: 0.5, sleepDebt: 0),
                rawIsSensible: { ($0.intensity == .hard || $0.intensity == .moderate || $0.intensity == .max) && noGymWeights($0) }),
            SyntheticFixture("green-after-hard-yesterday",
                pic(recovery: 70, yesterday: [YesterdaySession(type: "legs", strain: 16, durationMin: 70, avgHR: 140)]),
                rawIsSensible: { $0.intensity != .max && noGymWeights($0) }),

            // — Yellow / moderate: train but not max —
            SyntheticFixture("yellow-mild", pic(recovery: 55, hrvZ: -0.6),
                rawIsSensible: { $0.intensity != .max }),
            SyntheticFixture("yellow-hrv-down", pic(recovery: 50, hrvZ: -1.1, rhrDelta: 3),
                rawIsSensible: { $0.intensity == .moderate || $0.intensity == .easy || $0.intensity == .recovery }),
            SyntheticFixture("yellow-sleep-debt", pic(recovery: 58, sleepDebt: 2.5),
                rawIsSensible: { $0.intensity != .max }),

            // — RED / SEVERE: the prompt must pick recovery UNAIDED (anti-pattern) —
            SyntheticFixture("red-crashed", pic(recovery: 28, hrvZ: -1.8, rhrDelta: 6),
                rawIsSensible: { isRecoveryish($0) },
                antiPattern: { isRecoveryish($0) },
                diagnose: { "RED day but Haiku prescribed \($0.intensity.rawValue) \($0.modality)" }),
            SyntheticFixture("red-deep", pic(recovery: 20, hrvZ: -2.2, rhrDelta: 8, sleepDebt: 5),
                rawIsSensible: { isRecoveryish($0) },
                antiPattern: { isRecoveryish($0) }),
            SyntheticFixture("severe-illness-resp", pic(recovery: 55, respDelta: 2.5),
                rawIsSensible: { isRecoveryish($0) },
                antiPattern: { isRecoveryish($0) },
                diagnose: { "Illness signal but Haiku prescribed \($0.intensity.rawValue)" }),
            SyntheticFixture("severe-sleep-debt-yellow", pic(recovery: 50, sleepDebt: 4.5),
                rawIsSensible: { isRecoveryish($0) },
                antiPattern: { isRecoveryish($0) }),

            // — Pre-match (T-1): sharp but NOT heavy legs (anti-pattern) —
            SyntheticFixture("prematch-green", pic(recovery: 78, match: 1),
                rawIsSensible: { notHardLegs($0) },
                antiPattern: { notHardLegs($0) },
                diagnose: { "Match tomorrow but Haiku prescribed \($0.intensity.rawValue) \($0.modality)" }),
            SyntheticFixture("prematch-yellow", pic(recovery: 58, hrvZ: -0.8, match: 1),
                rawIsSensible: { notHardLegs($0) && $0.intensity != .max },
                antiPattern: { notHardLegs($0) }),
            SyntheticFixture("match-today", pic(recovery: 75, match: 0),
                rawIsSensible: { $0.intensity != .max },
                antiPattern: { notHardLegs($0) }),

            // — Subjective conflict: green Whoop but pain flag → route away —
            SyntheticFixture("green-but-knee-pain",
                pic(recovery: 80, checkIn: MorningCheckInSnapshot(mood: 3, stress: 4, soreness: ["knee": 9])),
                rawIsSensible: { s in
                    // Should not load legs hard with a knee pain flag.
                    let loadsLegs = s.blocks.contains { ($0.split?.lowercased().contains("leg") ?? false) }
                    return !loadsLegs || s.intensity == .easy || s.intensity == .recovery
                }),
            SyntheticFixture("green-high-stress",
                pic(recovery: 72, checkIn: MorningCheckInSnapshot(mood: 2, stress: 9, soreness: [:])),
                rawIsSensible: { $0.intensity != .max }),

            // — Overreach: ACWR spiking → back off —
            SyntheticFixture("overreach-acwr", pic(recovery: 62, acwr: 1.6),
                rawIsSensible: { $0.intensity != .max }),

            // — Cold-start: trends building (<30 days) → no trend claims, simple —
            SyntheticFixture("coldstart-day5", pic(recovery: 70, hrvZ: nil, rhrDelta: nil, validSamples: 5, historyDays: 5),
                rawIsSensible: { noGymWeights($0) }),
            SyntheticFixture("coldstart-day20-redrecovery", pic(recovery: 30, hrvZ: nil, validSamples: 10, historyDays: 20),
                rawIsSensible: { isRecoveryish($0) },
                antiPattern: { isRecoveryish($0) }),

            // — Gym-pointer discipline: a clear gym day must NOT emit weights —
            SyntheticFixture("gym-pointer-check", pic(recovery: 76),
                rawIsSensible: { noGymWeights($0) },
                diagnose: { _ in "gym block leaked sets/weights (must be a pointer)" }),

            // — Recovery-trending-up, green: a quality session is right —
            SyntheticFixture("fit-improving", pic(recovery: 85, hrvZ: 1.2, rhrDelta: -3),
                rawIsSensible: { $0.intensity != .recovery && noGymWeights($0) }),
        ]
    }
}
#endif
