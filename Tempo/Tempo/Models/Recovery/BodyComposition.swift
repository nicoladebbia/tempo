//
// BodyComposition.swift
// Tempo
//
// Daily body-composition snapshot (docs/INTELLIGENT_TRAINING_SYSTEM.md §4.3, Decision #11/#13).
// Withings → Apple Health → HealthKitService.fetchBodyComposition() → snapshotted
// here once/day so a 30-day trend exists for the monthly summary (§17). We store
// daily because bioimpedance fat%/muscle% swing ±2–3% on hydration alone (§12 G5),
// so the monthly report needs a robust trend (rolling median / fitted slope), not
// a month-end point-to-point delta — and that needs the daily series.
//

import Foundation
import SwiftData

@Model
final class BodyComposition {
    /// One snapshot per calendar day (the latest reading that day).
    @Attribute(.unique)
    var date: Date

    var weightKg: Double?
    var bodyFatPercent: Double?
    var leanMassKg: Double?

    /// When HealthKit says the underlying measurement was taken (may predate the
    /// snapshot date if Nicola didn't weigh in today — used to age-out stale reads).
    var measurementDate: Date?

    var capturedAt: Date

    init(
        date: Date,
        weightKg: Double? = nil,
        bodyFatPercent: Double? = nil,
        leanMassKg: Double? = nil,
        measurementDate: Date? = nil,
        capturedAt: Date = Date()
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.leanMassKg = leanMassKg
        self.measurementDate = measurementDate
        self.capturedAt = capturedAt
    }

    /// Maps to the pure-layer snapshot the ReadinessAssembler consumes.
    @Transient
    var snapshot: BodyCompSnapshot {
        BodyCompSnapshot(weightKg: weightKg, bodyFatPercent: bodyFatPercent, leanMassKg: leanMassKg)
    }
}
