//
// RecoveryEngineTests.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

@testable import Tempo
import XCTest

// MARK: - Recovery Engine Tests

// Per BUILD_PLAN Step 19.3 — Unit tests for recovery zone classification, sleep debt, trend detection.

final class RecoveryEngineTests: XCTestCase {
    private var engine: RecoveryEngine!

    override func setUp() {
        super.setUp()
        engine = RecoveryEngine()
    }

    // MARK: - Zone Classification

    // Per CROSS_DOC_AUDIT.md — RecoveryZone thresholds: green >= 67, yellow 34-66, red < 34

    func testClassifyZoneGreen() {
        XCTAssertEqual(engine.classifyZone(score: 80), .green)
        XCTAssertEqual(engine.classifyZone(score: 67), .green)
        XCTAssertEqual(engine.classifyZone(score: 100), .green)
    }

    func testClassifyZoneYellow() {
        XCTAssertEqual(engine.classifyZone(score: 50), .yellow)
        XCTAssertEqual(engine.classifyZone(score: 34), .yellow)
        XCTAssertEqual(engine.classifyZone(score: 66), .yellow)
    }

    func testClassifyZoneRed() {
        XCTAssertEqual(engine.classifyZone(score: 33), .red)
        XCTAssertEqual(engine.classifyZone(score: 10), .red)
        XCTAssertEqual(engine.classifyZone(score: 0), .red)
    }

    // MARK: - Sleep Debt Calculation

    // Per MODULE_RECOVERY.md Section 8.4

    func testSleepDebtNoData() {
        let debt = engine.calculateSleepDebt(recentSleep: [], target: 8.0)
        XCTAssertEqual(debt, 0)
    }

    func testSleepDebtPerfectSleep() {
        let debt = engine.calculateSleepDebt(recentSleep: [8, 8, 8, 8, 8], target: 8.0)
        XCTAssertEqual(debt, 0)
    }

    func testSleepDebtAccumulates() {
        // 7 days of 6h sleep with 8h target = 2h deficit/day × 7 = 14h debt
        let debt = engine.calculateSleepDebt(
            recentSleep: [6, 6, 6, 6, 6, 6, 6],
            target: 8.0
        )
        XCTAssertEqual(debt, 14.0, accuracy: 0.01)
    }

    func testSleepDebtCappedAt7Days() {
        // More than 7 days provided — only last 7 should be used
        let debt = engine.calculateSleepDebt(
            recentSleep: [4, 4, 4, 4, 4, 4, 4, 4, 4, 4], // 10 days of 4h
            target: 8.0
        )
        // Only last 7 days: 7 × 4h deficit = 28h
        XCTAssertEqual(debt, 28.0, accuracy: 0.01)
    }

    func testSleepDebtNoNegativeContribution() {
        // Sleeping more than target should not reduce debt
        let debt = engine.calculateSleepDebt(
            recentSleep: [10, 10, 10, 6, 6],
            target: 8.0
        )
        // Only 6h days contribute: 2 × 2h = 4h
        XCTAssertEqual(debt, 4.0, accuracy: 0.01)
    }

    // MARK: - RecoveryZone Properties

    func testRecoveryZoneDisplayName() {
        XCTAssertEqual(RecoveryZone.green.displayName, "Green")
        XCTAssertEqual(RecoveryZone.yellow.displayName, "Yellow")
        XCTAssertEqual(RecoveryZone.red.displayName, "Red")
    }

    func testRecoveryZoneInit() {
        XCTAssertEqual(RecoveryZone(score: 100), .green)
        XCTAssertEqual(RecoveryZone(score: 50), .yellow)
        XCTAssertEqual(RecoveryZone(score: 0), .red)
    }
}
