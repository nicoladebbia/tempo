//
// RecoveryEngineProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

protocol RecoveryEngineProtocol: Sendable {
    func generatePrescription(
        recovery: DailyRecovery,
        schedule: [CalendarEvent]
    ) -> DailyPrescription

    func classifyZone(score: Double) -> RecoveryZone

    func calculateSleepDebt(
        recentSleep: [Double],
        target: Double
    ) -> Double

    func detectTrends(
        recoveries: [DailyRecovery],
        days: Int
    ) -> [RecoveryInsight]
}
