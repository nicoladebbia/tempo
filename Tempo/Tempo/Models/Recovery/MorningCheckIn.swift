//
// MorningCheckIn.swift
// Tempo
//
// The subjective morning check-in (docs/INTELLIGENT_TRAINING_SYSTEM.md §4.2, Decision #8).
// A SEPARATE @Model — NOT fields on DailyRecovery — because:
//   • The ReadinessAssembler already consumes check-in as a separate parameter
//     (MorningCheckInSnapshot), distinct from DailyRecoverySnapshot.
//   • A check-in must be writable on a Whoop-DISCONNECTED day (§15.5: "Whoop
//     green but check-in says exhausted"). Storing it on DailyRecovery would
//     force a biometric-empty recovery row on a no-sync day, which would inflate
//     historyDayCount — the load-bearing field for the brain's ≥30-day gate.
//   • Different lifecycle: user-authored via a tap-card, not Whoop sync.
//
// Soreness is stored as a JSON string (bodyPart → 1–10) so the body-part list
// can evolve with ZERO schema change. The 1–10 scale is REQUIRED: D0's
// MorningCheckInSnapshot.painFlags fires at value >= 8, so a 1–5 card scale
// would silently kill §15.5 pain-routing.
//

import Foundation
import SwiftData

@Model
final class MorningCheckIn {
    /// One check-in per calendar day. Unique on the start-of-day date.
    @Attribute(.unique)
    var date: Date

    /// 1–5 (low→high energy/mood). nil = not answered.
    var mood: Int?

    /// 1–10 perceived stress. nil = not answered.
    var stress: Int?

    /// JSON-encoded `[bodyPart: 1–10]` soreness. nil/empty = none reported.
    /// 1–10 scale is contractual (see painFlags threshold in the snapshot).
    var sorenessRaw: String?

    var capturedAt: Date

    init(date: Date, mood: Int? = nil, stress: Int? = nil, soreness: [String: Int] = [:], capturedAt: Date = Date()) {
        self.date = Calendar.current.startOfDay(for: date)
        self.mood = mood
        self.stress = stress
        self.sorenessRaw = Self.encodeSoreness(soreness)
        self.capturedAt = capturedAt
    }

    // MARK: - Soreness round-trip (the bug-prone @Model ↔ snapshot join)

    /// Decoded soreness dict. Malformed/empty/nil JSON → `[:]` (never crashes).
    @Transient
    var soreness: [String: Int] {
        get { Self.decodeSoreness(sorenessRaw) }
        set { sorenessRaw = Self.encodeSoreness(newValue) }
    }

    static func encodeSoreness(_ dict: [String: Int]) -> String? {
        guard !dict.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(dict), let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    static func decodeSoreness(_ raw: String?) -> [String: Int] {
        guard let raw, let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    /// Maps to the pure-layer snapshot the ReadinessAssembler consumes.
    @Transient
    var snapshot: MorningCheckInSnapshot {
        MorningCheckInSnapshot(mood: mood, stress: stress, soreness: soreness)
    }
}
