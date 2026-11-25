//
// KitchenWordsTests.swift
// Tempo
//
// Counts in the Kitchen read the way a person says them: "1 pack" and
// "3 packs" (never "1packs" or "3pcs"), "1 day left", "1 serving left".
//

@testable import Tempo
import XCTest

@MainActor
final class KitchenWordsTests: XCTestCase {
    // MARK: Grocery rows

    func testGroceryQuantityKeepsASpaceAndTheRightNumber() {
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 1, unit: .packs), "1 pack")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 3, unit: .packs), "3 packs")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 3, unit: .pieces), "3 pcs")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 1, unit: .pieces), "1 pc")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 2, unit: .cans), "2 cans")
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 1, unit: .cans), "1 can")
    }

    func testWeightsAndVolumesStayCompact() {
        XCTAssertEqual(PantryQuantityFormatter.text(quantity: 500, unit: .grams), "500g")
    }

    // MARK: Use up soon

    func testUseUpSoonSaysTodayOneDayAndManyDays() {
        XCTAssertEqual(UseUpSoonCard.urgencyLabel(days: 0), "today")
        XCTAssertEqual(UseUpSoonCard.urgencyLabel(days: 1), "1 day")
        XCTAssertEqual(UseUpSoonCard.urgencyLabel(days: 2), "2 days")
        XCTAssertEqual(UseUpSoonCard.urgencyLabel(days: 7), "7 days")
    }

    // MARK: Supplements

    private func stockLine(servings: Double, daysLeft: Int? = nil) -> String? {
        let supplement = Supplement(name: "Creatine", kind: .creatine, servingsRemaining: servings)
        let dose = SupplementDose(
            supplementID: supplement.id, name: supplement.name, kind: .creatine, dosePerServing: "5 g",
            take: true, minutes: 8 * 60, anchor: nil, reason: ""
        )
        return SupplementShelfRow(supplement: supplement, dose: dose, daysLeft: daysLeft, needsReorder: false).stockLine
    }

    func testStockLineSaysOneServingAndManyServings() {
        XCTAssertEqual(stockLine(servings: 1), "1 serving left")
        XCTAssertEqual(stockLine(servings: 40), "40 servings left")
    }

    func testStockLineSaysOneDayAndManyDays() {
        XCTAssertEqual(stockLine(servings: 1, daysLeft: 1), "1 day left")
        XCTAssertEqual(stockLine(servings: 34, daysLeft: 34), "34 days left")
        XCTAssertEqual(stockLine(servings: 5, daysLeft: 0), "Out")
        XCTAssertNil(stockLine(servings: 0))
    }

    // MARK: The helper

    func testCountPluralisesOnlyWhenItIsNotOne() {
        XCTAssertEqual(FuelWords.count(0, "item"), "0 items")
        XCTAssertEqual(FuelWords.count(1, "item"), "1 item")
        XCTAssertEqual(FuelWords.count(2, "item"), "2 items")
        XCTAssertEqual(FuelWords.count(1, "serving"), "1 serving")
        XCTAssertEqual(FuelWords.count(2, "week"), "2 weeks")
    }
}
