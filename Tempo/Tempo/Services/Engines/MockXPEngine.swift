import Foundation

final class MockXPEngine: XPEngineProtocol, @unchecked Sendable {

    func calculateXP(
        from snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> [XPEvent] {
        [
            XPEvent(date: Date(), source: .workout, amount: 50, description: "Completed push workout"),
            XPEvent(date: Date(), source: .study, amount: 45, description: "2 pomodoro sessions"),
            XPEvent(date: Date(), source: .meal, amount: 50, description: "All meals logged"),
        ]
    }

    // Level = floor(sqrt(totalXP / 100))
    func currentLevel(totalXP: Int) -> Int {
        Int(sqrt(Double(totalXP) / 100.0))
    }

    func xpToNextLevel(totalXP: Int) -> Int {
        let current = currentLevel(totalXP: totalXP)
        let nextLevelXP = (current + 1) * (current + 1) * 100
        return nextLevelXP - totalXP
    }
}
