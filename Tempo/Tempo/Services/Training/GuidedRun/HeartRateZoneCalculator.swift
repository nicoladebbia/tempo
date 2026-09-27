//
// HeartRateZoneCalculator.swift
// Tempo
//
// Guided run mode — Apple Watch run mode §2: Z1-Z5 heart-rate zones so the
// wrist and the phone's guided-run screen both show the same band for a
// live BPM reading. Pure Foundation, no HealthKit — the Watch feeds real
// HKWorkoutSession BPM samples in; this only does the arithmetic, so it's
// shared verbatim with the TempoWatch target (project.yml) and unit-tested
// without any HealthKit dependency.
//

import Foundation

enum HeartRateZoneCalculator {
    /// Standard age-based estimate — the fallback whenever the athlete hasn't
    /// set their own max HR (`UserSettings.maxHeartRateOverride`).
    static func estimatedMaxHeartRate(age: Int) -> Double {
        Double(220 - age)
    }

    /// `override`, else the age estimate, else a generic default (220-30)
    /// so a fresh profile with neither still gets a usable zone instead of
    /// nil forever.
    static func maxHeartRate(age: Int?, override: Double?) -> Double {
        if let override, override > 0 {
            return override
        }
        if let age {
            return estimatedMaxHeartRate(age: age)
        }
        return estimatedMaxHeartRate(age: 30)
    }

    /// Z1 (<60%) … Z5 (≥90% of max) — the standard 5-zone split. `nil` for a
    /// non-positive reading (a bad sample, never shown).
    static func zone(bpm: Double, maxHeartRate: Double) -> Int? {
        guard bpm > 0, maxHeartRate > 0 else {
            return nil
        }
        let percent = bpm / maxHeartRate
        switch percent {
        case ..<0.6: return 1
        case 0.6 ..< 0.7: return 2
        case 0.7 ..< 0.8: return 3
        case 0.8 ..< 0.9: return 4
        default: return 5
        }
    }

    static func zoneLabel(_ zone: Int?) -> String {
        guard let zone else {
            return "—"
        }
        return "Z\(zone)"
    }
}
