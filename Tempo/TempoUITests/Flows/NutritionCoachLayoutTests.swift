//
// NutritionCoachLayoutTests.swift
// Tempo
//
//

import XCTest

// MARK: - Nutrition Coach Layout Tests

// The Coach page scrolls vertically only: a horizontal drag must not move it.

final class NutritionCoachLayoutTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testCoachPageDoesNotScrollHorizontally() {
        app.launchForTesting()
        app.tabBars.buttons["Nutrition"].tap()
        app.segmentedControls.buttons["Coach"].tap()

        let header = app.staticTexts["DAILY BRIEFING"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let startX = header.frame.minX
        attachScreenshot("coach-before-swipe")

        let page = app.scrollViews.firstMatch
        page.swipeLeft()
        XCTAssertEqual(header.frame.minX, startX, accuracy: 1, "Swipe left moved the Coach page")
        page.swipeRight()
        XCTAssertEqual(header.frame.minX, startX, accuracy: 1, "Swipe right moved the Coach page")

        let screenWidth = app.windows.firstMatch.frame.width
        XCTAssertLessThan(header.frame.maxX, screenWidth, "Card content runs past the screen edge")
        page.swipeUp()
        attachScreenshot("coach-after-scroll")
    }

    /// Every card spans the full width of the page.
    func testCoachCardsAreTheSameWidth() {
        app.launchForTesting()
        app.tabBars.buttons["Nutrition"].tap()
        app.segmentedControls.buttons["Coach"].tap()

        let daily = app.otherElements["coach.card.daily"]
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        let width = daily.frame.width
        app.scrollViews.firstMatch.swipeUp()
        for id in ["coach.card.suggestion", "coach.card.recovery", "coach.card.feedback"] {
            let card = app.otherElements[id]
            XCTAssertTrue(card.waitForExistence(timeout: 5), "\(id) missing")
            XCTAssertEqual(card.frame.width, width, accuracy: 1, "\(id) is not the same width as the other cards")
        }
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
