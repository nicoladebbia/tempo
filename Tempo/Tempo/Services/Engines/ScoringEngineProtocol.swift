import Foundation

// MARK: - Score Breakdown

struct ScoreBreakdown: Sendable {
    let body: Int
    let fuel: Int
    let mind: Int
    let move: Int

    var total: Int { body + fuel + mind + move }
}

// MARK: - Protocol

protocol ScoringEngineProtocol: Sendable {
    func calculateDailyScore(
        snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> Int

    func scoreBreakdown(snapshot: DailySnapshot) -> ScoreBreakdown
}
