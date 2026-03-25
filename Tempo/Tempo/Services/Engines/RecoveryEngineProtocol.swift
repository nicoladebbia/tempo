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
