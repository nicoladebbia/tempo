//
// MockRecoveryEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

final class MockRecoveryEngine: RecoveryEngineProtocol, @unchecked Sendable {
    func generatePrescription(
        recovery: DailyRecovery,
        schedule: [CalendarEvent]
    ) -> DailyPrescription {
        // NOTE: Do NOT set dailyRecovery here — the caller sets the
        // relationship after both objects are in the SwiftData context.
        DailyPrescription(
            date: recovery.date,
            trainingRec: "Moderate training — keep intensity at 70% max",
            trainingDetail: "Upper body focus. Avoid heavy compounds.",
            nutritionRecs: [
                "Extra carbs around workout window",
                "30g protein within 30 min post-workout",
                "2.5L water minimum",
            ],
            bedtimeTarget: Calendar.current.date(
                bySettingHour: 22, minute: 30, second: 0, of: Date()
            ),
            caffeineCutoff: Calendar.current.date(
                bySettingHour: 14, minute: 0, second: 0, of: Date()
            ),
            hydrationTargetMl: 2500,
            warnings: ["HRV trending down 3 days — consider extra rest"]
        )
    }

    func classifyZone(score: Double) -> RecoveryZone {
        RecoveryZone(score: score)
    }

    func calculateSleepDebt(
        recentSleep: [Double],
        target: Double
    ) -> Double {
        let avgSleep = recentSleep.isEmpty ? 0 : recentSleep.reduce(0, +) / Double(recentSleep.count)
        return max(0, target - avgSleep)
    }

    func detectTrends(
        recoveries: [DailyRecovery],
        days: Int
    ) -> [RecoveryInsight] {
        [
            RecoveryInsight(
                date: Date(),
                type: .pattern,
                title: "HRV Declining",
                body: "Your HRV has dropped 15% over the last 5 days. Consider a deload.",
                dataPointsJSON: try? JSONSerialization.data(withJSONObject: [
                    ["day": 1, "hrv": 52],
                    ["day": 2, "hrv": 48],
                    ["day": 3, "hrv": 45],
                    ["day": 4, "hrv": 43],
                    ["day": 5, "hrv": 42],
                ]),
                confidence: 0.82
            ),
        ]
    }
}
