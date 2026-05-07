//
// ScoringEngineProtocol.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - ScoreBreakdown

struct ScoreBreakdown {
    let body: Int
    let fuel: Int
    let mind: Int
    let move: Int

    var total: Int {
        body + fuel + mind + move
    }
}

// MARK: - ScoringEngineProtocol

protocol ScoringEngineProtocol: Sendable {
    func calculateDailyScore(
        snapshot: DailySnapshot,
        accountability: DailyAccountability
    ) -> Int

    func scoreBreakdown(snapshot: DailySnapshot) -> ScoreBreakdown
}
