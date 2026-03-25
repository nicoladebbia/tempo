import Foundation

final class MockScoringEngine: ScoringEngineProtocol, @unchecked Sendable {

    func calculateDailyScore(
        snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> Int {
        78
    }

    func scoreBreakdown(snapshot: DailySnapshot) -> ScoreBreakdown {
        ScoreBreakdown(body: 22, fuel: 18, mind: 20, move: 18)
    }
}
