//
// DailyNutritionMealEntriesTests.swift
// Tempo
//
// T3 #3 — DailyNutritionSummaryView's meal list was fake: fixed
// "Breakfast/Lunch/Snack/Dinner" labels, "--" times, calories evenly split
// across the logged count. It now maps today's real PlannedMeals; these pin
// that mapping.
//

@testable import Tempo
import XCTest

@MainActor
final class DailyNutritionMealEntriesTests: XCTestCase {
    func testMapsRealMealsInEatingOrder() throws {
        let today = Date()
        let eatenAt = try XCTUnwrap(Calendar.current.date(bySettingHour: 8, minute: 5, second: 0, of: today))
        let dinner = PlannedMeal(dayDate: today, mealNumber: 3, mealName: "Salmon Bowl", scheduledTime: "19:30", totalCalories: 820.4)
        let breakfast = PlannedMeal(
            dayDate: today, mealNumber: 1, mealName: "Oats & Whey", scheduledTime: "07:45",
            foods: [
                PlannedFood(name: "Oats", quantityGrams: 80, calories: 300, proteinG: 10, carbsG: 54, fatG: 5),
                PlannedFood(name: "Whey", quantityGrams: 30, calories: 120, proteinG: 24, carbsG: 3, fatG: 1),
            ],
            totalCalories: 420, status: .eaten, actualEatenAt: eatenAt
        )
        let lunch = PlannedMeal(
            dayDate: today,
            mealNumber: 2,
            mealName: "Chicken Wrap",
            scheduledTime: "13:00",
            totalCalories: 650,
            status: .skipped
        )

        let entries = NutritionMealEntry.entries(from: [dinner, breakfast, lunch])

        XCTAssertEqual(entries.map(\.type), ["Oats & Whey", "Chicken Wrap", "Salmon Bowl"])
        XCTAssertEqual(entries.map(\.id), [breakfast.id, lunch.id, dinner.id])

        XCTAssertEqual(entries[0].status, .logged)
        XCTAssertEqual(entries[0].time, TempoDateFormatters.timeOnly.string(from: eatenAt), "Eaten → actual eat time")
        XCTAssertEqual(entries[0].calories, 420)
        XCTAssertEqual(entries[0].items, ["Oats", "Whey"])

        XCTAssertEqual(entries[1].status, .skipped)
        XCTAssertNil(entries[1].calories, "Skipped meals show no kcal")

        XCTAssertEqual(entries[2].status, .planned)
        XCTAssertEqual(entries[2].time, "19:30")
        XCTAssertEqual(entries[2].calories, 820)
    }

    func testNoMealsGivesNoRows() {
        XCTAssertTrue(NutritionMealEntry.entries(from: []).isEmpty)
    }
}
