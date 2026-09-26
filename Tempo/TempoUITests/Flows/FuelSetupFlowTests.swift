//
// FuelSetupFlowTests.swift
// Tempo
//
// Nutrition → Plan → Generate (no profile yet) → Fuel setup: the talk-or-type
// screen, the manual path into the review form, a weekday's routine with a
// meal out, and Save.
//

import XCTest

final class FuelSetupFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testManualFuelSetupWithAMealOut() {
        app.launchForTesting(extraArguments: [TestLaunchArguments.emptyStore])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        app.tabBars.buttons["Nutrition"].tap()
        let planSegment = app.segmentedControls.buttons["Plan"]
        XCTAssertTrue(planSegment.waitForExistence(timeout: 10))
        planSegment.tap()

        let generate = app.buttons["Generate New Plan"]
        XCTAssertTrue(generate.waitForExistence(timeout: 10))
        generate.tap()

        XCTAssertTrue(app.staticTexts["Talk me through your week."].waitForExistence(timeout: 10))
        attach("01-fuel-talk")
        app.buttons["fuelSetupManual"].tap()

        let weight = app.textFields["fuelWeight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        for (id, value) in [("fuelWeight", "78"), ("fuelHeight", "183"), ("fuelAge", "24")] {
            let field = app.textFields[id]
            field.tap()
            field.typeText(value)
        }
        attach("02-fuel-review")
        app.toolbars.buttons["Done"].tap()

        let monday = app.buttons["fuelDay1"]
        for _ in 0 ..< 6 where !monday.isHittable {
            app.swipeUp()
        }
        monday.tap()
        XCTAssertTrue(app.navigationBars["Monday"].waitForExistence(timeout: 5))
        let mealOut = app.buttons["Add a meal out"]
        for _ in 0 ..< 4 where !mealOut.isHittable {
            app.swipeUp()
        }
        mealOut.tap()
        let restaurants = app.textFields["Restaurants (usual first)"]
        XCTAssertTrue(restaurants.waitForExistence(timeout: 5))
        restaurants.tap()
        restaurants.typeText("Panera Bread")
        attach("03-fuel-monday")
        app.navigationBars["Monday"].buttons.firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'eat Panera Bread 13:00'")).firstMatch
                .waitForExistence(timeout: 5),
            "Monday summary shows the meal out"
        )
        attach("04-fuel-week")
        app.buttons["fuelSetupSave"].tap()
        XCTAssertTrue(app.staticTexts["Talk me through your week."].waitForNonExistence(timeout: 15), "Sheet closes after saving")
    }
}
