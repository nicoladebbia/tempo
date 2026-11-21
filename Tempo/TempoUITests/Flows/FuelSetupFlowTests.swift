//
// FuelSetupFlowTests.swift
// Tempo
//
// Nutrition → Plan → Generate (no profile yet) → Fuel setup: the talk-or-type
// screen, the manual path into the section overview, the You flow, a weekday's routine with a
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

        // Overview: plan generation is blocked on the required sections, with
        // one message and one button that chains through them.
        let blocked = app.staticTexts["fuelSetupBlocked"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 10))
        XCTAssertTrue(blocked.label.contains("Finish You, Goal and Meals"), "names exactly what's missing: \(blocked.label)")
        XCTAssertTrue(app.buttons["fuelSetupFinish"].exists, "Finish setup card on top")
        attach("02-fuel-overview")
        app.buttons["fuelSetupFinishRequired"].tap()

        // You: weight, height and age share ONE screen.
        for (id, value) in [("fuelWeight", "78"), ("fuelHeight", "183"), ("fuelAge", "24")] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 10), id)
            field.tap()
            field.typeText(value)
            app.toolbars.buttons["Done"].tap()
        }
        attach("03-fuel-you-body")
        app.buttons["fuelFlowNext"].tap()
        app.buttons["Male"].tap()
        app.buttons["fuelFlowNext"].tap()
        // Body fat is optional: Skip saves You and opens Goal.
        XCTAssertTrue(app.buttons["fuelFlowSkip"].waitForExistence(timeout: 5))
        app.buttons["fuelFlowSkip"].tap()

        // Goal (chain: "Save & next: Meals & eating window").
        let maintain = app.buttons["Maintain, Hold your weight, eat well"]
        XCTAssertTrue(maintain.waitForExistence(timeout: 10))
        maintain.tap()
        app.buttons["fuelFlowNext"].tap()
        XCTAssertTrue(app.buttons["Save & next: Meals & eating window"].waitForExistence(timeout: 5))
        app.buttons["fuelFlowSave"].tap()

        // Meals: count + breakfast on one screen, then the optional window.
        XCTAssertTrue(app.buttons["fuelFlowNext"].waitForExistence(timeout: 10))
        attach("04-fuel-meals")
        app.buttons["fuelFlowNext"].tap()
        XCTAssertTrue(app.buttons["Save & finish"].waitForExistence(timeout: 5))
        app.buttons["fuelFlowSave"].tap()

        // Back on the overview, nothing blocks any more.
        XCTAssertTrue(app.buttons["fuelSetupSave"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["fuelSetupBlocked"].exists)

        // "Your week" flow, first screen: the seven days.
        let week = app.buttons["fuelSection.week"]
        XCTAssertTrue(week.waitForExistence(timeout: 10))
        week.tap()

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
        attach("05-fuel-week")
        app.buttons["fuelFlowNext"].tap()
        app.buttons["fuelFlowNext"].tap()
        app.buttons["fuelFlowSave"].tap()
        app.buttons["fuelSetupSave"].tap()
        XCTAssertTrue(app.staticTexts["Talk me through your week."].waitForNonExistence(timeout: 15), "Sheet closes after saving")
    }
}
