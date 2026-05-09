//
// ScoringEngineTests.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

@testable import Tempo
import XCTest

// MARK: - Scoring Engine Tests

// Per BUILD_PLAN Step 19.3 — Unit tests for daily score calculation, component scores, quadrant scores.

final class ScoringEngineTests: XCTestCase {
    private var engine: ScoringEngine!

    override func setUp() {
        super.setUp()
        engine = ScoringEngine()
    }

    // MARK: - Daily Score (Weighted Composite)

    // Weights: NN 40%, Training 20%, Nutrition 20%, Recovery 10%, Activity 10%

    @MainActor
    func testPerfectDayScore() {
        let snapshot = DailySnapshot(
            date: Date(),
            recoveryScore: 80,
            sleepScore: 0.9,
            caloriesConsumed: 2200,
            calorieTarget: 2200,
            proteinActual: 160,
            proteinTarget: 160,
            mealsLogged: 3,
            mealsPlanned: 3,
            studyMinutes: 120,
            studyTarget: 120,
            steps: 12000,
            activeCalories: 500,
            workoutCompleted: true
        )
        let accountability = DailyAccountability(date: Date(), leisureUnlocked: true)
        // No NN progress attached → totalCount = 0 → NN score = 0
        // Training: 100 (workout done) → 20
        // Nutrition: meals 40 + cal 30 + protein 30 = 100 → 20
        // Recovery: sleep 45 + recovery 40 = 85 → 8.5
        // Activity: steps 70 + cal 30 = 100 → 10
        // Total ≈ 0 + 20 + 20 + 8 + 10 = 58 (NN has no progress entries)
        let score = engine.calculateDailyScore(snapshot: snapshot, accountability: accountability)
        XCTAssertGreaterThanOrEqual(score, 50)
        XCTAssertLessThanOrEqual(score, 100)
    }

    @MainActor
    func testEmptyDayScore() {
        let snapshot = DailySnapshot(
            date: Date(),
            mealsLogged: 0,
            mealsPlanned: 3,
            studyMinutes: 0,
            studyTarget: 120
        )
        let accountability = DailyAccountability(date: Date())
        let score = engine.calculateDailyScore(snapshot: snapshot, accountability: accountability)
        XCTAssertEqual(score, 0)
    }

    @MainActor
    func testScoreClampedTo100() {
        // Even with extreme values, score should never exceed 100
        let snapshot = DailySnapshot(
            date: Date(),
            recoveryScore: 100,
            sleepScore: 1.0,
            caloriesConsumed: 2200,
            calorieTarget: 2200,
            proteinActual: 200,
            proteinTarget: 160,
            mealsLogged: 5,
            mealsPlanned: 3,
            studyMinutes: 300,
            studyTarget: 120,
            steps: 20000,
            activeCalories: 1000,
            workoutCompleted: true
        )
        let accountability = DailyAccountability(date: Date())
        let score = engine.calculateDailyScore(snapshot: snapshot, accountability: accountability)
        XCTAssertLessThanOrEqual(score, 100)
        XCTAssertGreaterThanOrEqual(score, 0)
    }

    @MainActor
    func testScoreClampedTo0() {
        let snapshot = DailySnapshot(date: Date(), mealsLogged: 0, mealsPlanned: 0, studyMinutes: 0, studyTarget: 0)
        let accountability = DailyAccountability(date: Date())
        let score = engine.calculateDailyScore(snapshot: snapshot, accountability: accountability)
        XCTAssertGreaterThanOrEqual(score, 0)
    }

    // MARK: - Training Score

    @MainActor
    func testTrainingScoreWorkoutComplete() {
        let snapshot = DailySnapshot(date: Date(), workoutCompleted: true)
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        XCTAssertEqual(breakdown.trainingScore, 100)
    }

    @MainActor
    func testTrainingScoreHighStrain() {
        let snapshot = DailySnapshot(date: Date(), strain: 15.0)
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        XCTAssertEqual(breakdown.trainingScore, 60)
    }

    @MainActor
    func testTrainingScoreNoWorkout() {
        let snapshot = DailySnapshot(date: Date())
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        XCTAssertEqual(breakdown.trainingScore, 0)
    }

    // MARK: - Nutrition Score

    @MainActor
    func testNutritionScorePerfect() {
        let snapshot = DailySnapshot(
            date: Date(),
            caloriesConsumed: 2200,
            calorieTarget: 2200,
            proteinActual: 160,
            proteinTarget: 160,
            mealsLogged: 3,
            mealsPlanned: 3
        )
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        // Meals: 40, Calories: 30, Protein: 30 = 100
        XCTAssertEqual(breakdown.nutritionScore, 100)
    }

    @MainActor
    func testNutritionScoreNoMeals() {
        let snapshot = DailySnapshot(date: Date(), mealsLogged: 0, mealsPlanned: 0)
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        XCTAssertEqual(breakdown.nutritionScore, 0)
    }

    @MainActor
    func testNutritionScorePartialMeals() {
        let snapshot = DailySnapshot(date: Date(), mealsLogged: 2, mealsPlanned: 4)
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        // mealRatio = 0.5, score = 0.5 * 40 = 20
        XCTAssertEqual(breakdown.nutritionScore, 20)
    }

    // MARK: - Recovery Score

    @MainActor
    func testRecoveryScoreFull() {
        let snapshot = DailySnapshot(date: Date(), recoveryScore: 100, sleepScore: 1.0)
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        // sleep: 1.0 * 50 = 50, recovery: (100/100)*50 = 50 → 100
        XCTAssertEqual(breakdown.recoveryScore, 100)
    }

    @MainActor
    func testRecoveryScoreNilData() {
        let snapshot = DailySnapshot(date: Date())
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        XCTAssertEqual(breakdown.recoveryScore, 0)
    }

    // MARK: - Activity Score

    @MainActor
    func testActivityScoreHighStepsAndCalories() {
        let snapshot = DailySnapshot(date: Date(), steps: 12000, activeCalories: 500)
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        // steps >= 12000 → 70, cal >= 500 → 30, total = 100
        XCTAssertEqual(breakdown.activityScore, 100)
    }

    @MainActor
    func testActivityScoreNoData() {
        let snapshot = DailySnapshot(date: Date())
        let accountability = DailyAccountability(date: Date())
        let breakdown = engine.detailedBreakdown(snapshot: snapshot, accountability: accountability)
        XCTAssertEqual(breakdown.activityScore, 0)
    }

    // MARK: - Quadrant Scores (ScoreBreakdown)

    @MainActor
    func testScoreBreakdownTotalMax100() {
        let snapshot = DailySnapshot(
            date: Date(),
            recoveryScore: 100,
            hrv: 80,
            rhr: 55,
            sleepScore: 1.0,
            caloriesConsumed: 2200,
            calorieTarget: 2200,
            proteinActual: 160,
            proteinTarget: 160,
            mealsLogged: 3,
            mealsPlanned: 3,
            studyMinutes: 120,
            studyTarget: 120,
            steps: 12000,
            activeCalories: 500,
            workoutCompleted: true
        )
        let breakdown = engine.scoreBreakdown(snapshot: snapshot)
        XCTAssertLessThanOrEqual(breakdown.total, 100)
        XCTAssertLessThanOrEqual(breakdown.body, 25)
        XCTAssertLessThanOrEqual(breakdown.fuel, 25)
        XCTAssertLessThanOrEqual(breakdown.mind, 25)
        XCTAssertLessThanOrEqual(breakdown.move, 25)
    }

    @MainActor
    func testScoreBreakdownMindQuadrant() {
        // Study 120 of 120 → compliance 1.0 → mind = 25
        let snapshot = DailySnapshot(date: Date(), studyMinutes: 120, studyTarget: 120)
        let breakdown = engine.scoreBreakdown(snapshot: snapshot)
        XCTAssertEqual(breakdown.mind, 25)
    }

    @MainActor
    func testScoreBreakdownMindNoTarget() {
        let snapshot = DailySnapshot(date: Date(), studyMinutes: 0, studyTarget: 0)
        let breakdown = engine.scoreBreakdown(snapshot: snapshot)
        XCTAssertEqual(breakdown.mind, 0)
    }
}
