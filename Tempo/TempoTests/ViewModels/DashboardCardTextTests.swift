//
// DashboardCardTextTests.swift
// Tempo
//
// The four Dashboard cards share the Body layout; these pin the short
// strings each quadrant feeds into it.
//

@testable import Tempo
import XCTest

@MainActor
final class DashboardCardTextTests: XCTestCase {
    // MARK: - Fuel

    private func fuel(consumed: Int? = 0, target: Int? = 2400) -> FuelQuadrantData {
        FuelQuadrantData(
            caloriesConsumed: consumed, calorieTarget: target,
            proteinGrams: 0, proteinTarget: 180,
            carbsGrams: 0, carbsTarget: 280,
            fatGrams: 0, fatTarget: 80,
            mealsLogged: nil, mealsPlanned: nil,
            isConnected: false, lastSync: nil
        )
    }

    func testMacroProgressShowsZeroBeforeFirstMeal() {
        XCTAssertEqual(FuelQuadrantData.macroProgress(current: nil, target: 180), "0 / 180g")
        XCTAssertEqual(FuelQuadrantData.macroProgress(current: 142, target: 180), "142 / 180g")
        XCTAssertEqual(FuelQuadrantData.macroProgress(current: 10, target: nil), "--")
    }

    func testCaloriesCaptionUsesTarget() {
        XCTAssertEqual(fuel(target: 2400).caloriesCaption, "kcal of \(fuel().formattedCalorieTarget)")
        XCTAssertEqual(fuel(target: nil).caloriesCaption, "kcal of --")
    }

    func testFootnotePrefersNextMealThenLastEatenThenNudge() {
        var data = fuel()
        XCTAssertEqual(data.cardFootnote, "No meals logged yet")

        data.lastEatenAt = Date().addingTimeInterval(-2 * 3600)
        XCTAssertEqual(data.cardFootnote, "Last meal 2h ago")

        data.nextMeal = PlannedMeal(dayDate: Date(), mealName: "Lunch", scheduledTime: "13:00")
        XCTAssertEqual(data.cardFootnote, "Next: Lunch · 13:00")
    }

    // MARK: - Move

    func testWorkoutSummary() {
        var data = MoveQuadrantData.empty
        XCTAssertEqual(data.workoutSummary, "--")
        data.workoutStatus = .restDay
        XCTAssertEqual(data.workoutSummary, "Rest")
        data.workoutStatus = .planned
        XCTAssertEqual(data.workoutSummary, "Planned")
        data.workoutName = "Push"
        XCTAssertEqual(data.workoutSummary, "Push")
        data.workoutStatus = .completed
        XCTAssertEqual(data.workoutSummary, "Done")
    }

    func testStepsGoalText() {
        var data = MoveQuadrantData.empty
        data.stepsTarget = 8000
        let formatted = NumberFormatter.localizedString(from: 8000, number: .decimal)
        XCTAssertEqual(data.stepsGoalText, "Goal \(formatted)")
    }

    // MARK: - Mind

    func testStudyCaptionAndProgress() {
        var data = MindQuadrantData.empty // 0 of 120 min
        XCTAssertFalse(data.hasHitStudyTarget)
        XCTAssertEqual(data.studyCaption, "Study today")
        XCTAssertEqual(data.studyProgressText, "0% of target")

        data.studyMinutesToday = 54
        XCTAssertEqual(data.studyProgressText, "45% of target")

        data.studyMinutesToday = 120
        XCTAssertTrue(data.hasHitStudyTarget)
        XCTAssertEqual(data.studyCaption, "Target hit")
    }

    func testNoStudyTargetIsNeverHit() {
        var data = MindQuadrantData.empty
        data.studyTargetMinutes = 0
        XCTAssertFalse(data.hasHitStudyTarget)
        XCTAssertEqual(data.studyProgressText, "No target set")
    }

    // MARK: - Auto-sync

    func testAutoRefreshEveryFiveMinutes() {
        XCTAssertEqual(DashboardViewModel.autoRefreshInterval, .seconds(300))
    }
}
