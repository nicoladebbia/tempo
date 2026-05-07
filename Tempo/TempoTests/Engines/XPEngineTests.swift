import XCTest
@testable import Tempo

// MARK: - XP Engine Tests
// Per BUILD_PLAN Step 19.3 — Unit tests for XP calculation, level formula.
// Updated for new LevelSystem-based level thresholds.

final class XPEngineTests: XCTestCase {

    private var engine: XPEngine!

    override func setUp() {
        super.setUp()
        engine = XPEngine()
    }

    // MARK: - Level Calculation (LevelSystem-based)

    func testLevel1At0XP() {
        // Level 1: Recruit starts at 0 XP
        XCTAssertEqual(engine.currentLevel(totalXP: 0), 1)
    }

    func testLevel1At99XP() {
        XCTAssertEqual(engine.currentLevel(totalXP: 99), 1)
    }

    func testLevel2At100XP() {
        XCTAssertEqual(engine.currentLevel(totalXP: 100), 2)
    }

    func testLevel5At500XP() {
        // Level 5: Soldier starts at 500 XP
        XCTAssertEqual(engine.currentLevel(totalXP: 500), 5)
    }

    func testLevel10At2000XP() {
        // Level 10: Warrior starts at 2000 XP
        XCTAssertEqual(engine.currentLevel(totalXP: 2000), 10)
    }

    func testLevel15At5000XP() {
        // Level 15: Captain starts at 5000 XP
        XCTAssertEqual(engine.currentLevel(totalXP: 5000), 15)
    }

    func testLevel20At10000XP() {
        // Level 20: Commander starts at 10000 XP
        XCTAssertEqual(engine.currentLevel(totalXP: 10000), 20)
    }

    func testLevel25At20000XP() {
        // Level 25: General starts at 20000 XP
        XCTAssertEqual(engine.currentLevel(totalXP: 20000), 25)
    }

    func testLevel30At50000XP() {
        // Level 30: Legend starts at 50000 XP
        XCTAssertEqual(engine.currentLevel(totalXP: 50000), 30)
    }

    func testLevelNegativeXP() {
        XCTAssertEqual(engine.currentLevel(totalXP: -100), 1)
    }

    // MARK: - XP to Next Level

    func testXPToNextLevelFrom0() {
        // Level 1 (0 XP), need 100 for level 2
        XCTAssertEqual(engine.xpToNextLevel(totalXP: 0), 100)
    }

    func testXPToNextLevelFrom50() {
        // Level 1 (50 XP), need 50 more for level 2 (100 total)
        XCTAssertEqual(engine.xpToNextLevel(totalXP: 50), 50)
    }

    func testXPToNextLevelFromExactLevel() {
        // At exactly level 2 (100 XP), need 150 more for level 3 (250 total)
        XCTAssertEqual(engine.xpToNextLevel(totalXP: 100), 150)
    }

    // MARK: - Level Progress

    func testLevelProgressAt0() {
        XCTAssertEqual(engine.levelProgress(totalXP: 0), 0, accuracy: 0.01)
    }

    func testLevelProgressMidway() {
        // At 50 XP, level 1 (0-100 range), so 50% progress
        XCTAssertEqual(engine.levelProgress(totalXP: 50), 0.5, accuracy: 0.01)
    }

    func testLevelProgressAtExactLevel() {
        // At 100 XP, just reached level 2, 0% progress to level 3
        XCTAssertEqual(engine.levelProgress(totalXP: 100), 0, accuracy: 0.01)
    }

    // MARK: - Level Names

    func testLevelNameRecruit() {
        XCTAssertEqual(engine.levelName(for: 1), "Recruit")
    }

    func testLevelNameSoldier() {
        XCTAssertEqual(engine.levelName(for: 5), "Soldier")
    }

    func testLevelNameWarrior() {
        XCTAssertEqual(engine.levelName(for: 10), "Warrior")
    }

    func testLevelNameCaptain() {
        XCTAssertEqual(engine.levelName(for: 15), "Captain")
    }

    func testLevelNameCommander() {
        XCTAssertEqual(engine.levelName(for: 20), "Commander")
    }

    func testLevelNameGeneral() {
        XCTAssertEqual(engine.levelName(for: 25), "General")
    }

    func testLevelNameLegend() {
        XCTAssertEqual(engine.levelName(for: 30), "Legend")
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

    // MARK: - Streak Milestones

    func testStreakMilestone7Days() {
        let event = engine.streakMilestoneXP(streakCount: 7)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.amount, 200)
    }

    func testStreakMilestone14Days() {
        let event = engine.streakMilestoneXP(streakCount: 14)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.amount, 500)
    }

    func testStreakMilestone30Days() {
        let event = engine.streakMilestoneXP(streakCount: 30)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.amount, 1000)
    }

    func testStreakMilestone60Days() {
        let event = engine.streakMilestoneXP(streakCount: 60)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.amount, 2000)
    }

    func testStreakMilestone100Days() {
        let event = engine.streakMilestoneXP(streakCount: 100)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.amount, 5000)
    }

    func testNoStreakMilestoneAt8Days() {
        XCTAssertNil(engine.streakMilestoneXP(streakCount: 8))
    }

    // MARK: - XP Earning Categories

    func testXPEarningCategoriesNotEmpty() {
        XCTAssertFalse(XPEngine.xpEarningCategories.isEmpty)
        XCTAssertGreaterThanOrEqual(XPEngine.xpEarningCategories.count, 10)
    }
}
