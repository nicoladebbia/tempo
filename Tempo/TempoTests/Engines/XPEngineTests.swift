import XCTest
@testable import Tempo

// MARK: - XP Engine Tests
// Per BUILD_PLAN Step 19.3 — Unit tests for XP calculation, level formula.

final class XPEngineTests: XCTestCase {

    private var engine: XPEngine!

    override func setUp() {
        super.setUp()
        engine = XPEngine()
    }

    // MARK: - Level Calculation
    // Per BUILD_PLAN 10.7: Level = floor(sqrt(totalXP / 100))

    func testLevel0At0XP() {
        XCTAssertEqual(engine.currentLevel(totalXP: 0), 0)
    }

    func testLevel0At99XP() {
        XCTAssertEqual(engine.currentLevel(totalXP: 99), 0)
    }

    func testLevel1At100XP() {
        XCTAssertEqual(engine.currentLevel(totalXP: 100), 1)
    }

    func testLevel2At400XP() {
        XCTAssertEqual(engine.currentLevel(totalXP: 400), 2)
    }

    func testLevel3At900XP() {
        XCTAssertEqual(engine.currentLevel(totalXP: 900), 3)
    }

    func testLevel10At10000XP() {
        XCTAssertEqual(engine.currentLevel(totalXP: 10000), 10)
    }

    func testLevelNegativeXP() {
        XCTAssertEqual(engine.currentLevel(totalXP: -100), 0)
    }

    // MARK: - XP to Next Level

    func testXPToNextLevelFrom0() {
        // Level 0, need 100 for level 1
        XCTAssertEqual(engine.xpToNextLevel(totalXP: 0), 100)
    }

    func testXPToNextLevelFrom50() {
        // Level 0, need 50 more for level 1 (100 total)
        XCTAssertEqual(engine.xpToNextLevel(totalXP: 50), 50)
    }

    func testXPToNextLevelFromExactLevel() {
        // At exactly level 1 (100 XP), need 300 more for level 2 (400 total)
        XCTAssertEqual(engine.xpToNextLevel(totalXP: 100), 300)
    }

    // MARK: - Level Progress

    func testLevelProgressAt0() {
        XCTAssertEqual(engine.levelProgress(totalXP: 0), 0, accuracy: 0.01)
    }

    func testLevelProgressMidway() {
        // At 50 XP, level 0, need 100 for level 1, so 50% progress
        XCTAssertEqual(engine.levelProgress(totalXP: 50), 0.5, accuracy: 0.01)
    }

    func testLevelProgressAtExactLevel() {
        // At 100 XP, just reached level 1, 0% progress to level 2
        XCTAssertEqual(engine.levelProgress(totalXP: 100), 0, accuracy: 0.01)
    }

    // MARK: - Streak XP

    func testNoStreakBonusBelow7Days() {
        XCTAssertNil(engine.streakXP(streakCount: 6))
    }

    func testWeeklyStreakBonus() {
        let event = engine.streakXP(streakCount: 7)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.amount, 25)
    }

    func testMonthlyStreakBonus() {
        let event = engine.streakXP(streakCount: 30)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.amount, 50)
    }

    func test29DayStreakGetsWeeklyBonus() {
        let event = engine.streakXP(streakCount: 29)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.amount, 25)
    }
}
