import Foundation

protocol XPEngineProtocol: Sendable {
    func calculateXP(
        from snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> [XPEvent]

    func currentLevel(totalXP: Int) -> Int

    func xpToNextLevel(totalXP: Int) -> Int
}
