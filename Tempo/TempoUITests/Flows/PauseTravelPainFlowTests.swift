//
// PauseTravelPainFlowTests.swift
// Tempo
//
// Screenshots the pause/travel-pain feature end to end: the paused "Today"
// card and the away-mode sheet's resume option, then (a separate scenario,
// since a pause blocks the whole day) the travel hotel-swap label + pain
// caution chip on Today, the "This hurts" flow, and the trainer report's new
// football/pain/pauses/travel sections. Drives `PauseTravelPainUITestSeed`.
//

import XCTest

// MARK: - PauseTravelPainFlowTests

final class PauseTravelPainFlowTests: XCTestCase {
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

    // MARK: - Scenario 1: paused

    func testPausedTodayCardAndAwayModeResume() {
        app.launchForTesting(extraArguments: [PauseTravelPainUITestSeedArguments.pauseActive])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["PAUSED"].waitForExistence(timeout: 10))
        attach("pause-01-today-paused-card")

        app.buttons["More"].tap()
        let away = app.buttons["Away from the gym"]
        XCTAssertTrue(away.waitForExistence(timeout: 5))
        away.tap()
        XCTAssertTrue(app.navigationBars["Away from the gym"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Currently paused"].waitForExistence(timeout: 5))
        attach("pause-02-away-mode-sheet-currently-paused")
    }

    // MARK: - Scenario 2: travel swap + pain caution + this-hurts flow + report

    func testTravelSwapPainCautionAndTrainerReport() {
        app.launchForTesting(extraArguments: [PauseTravelPainUITestSeedArguments.travelPain])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        // Hotel-swap label + caution chip render inline in Today's exercise list.
        XCTAssertTrue(app.staticTexts["Hotel swap for Romanian Deadlift"].waitForExistence(timeout: 10))
        attach("travel-01-today-hotel-swap-and-caution-chip")

        // "This hurts" — long-press the swapped exercise row's card.
        let exerciseCard = app.staticTexts["Hotel swap for Romanian Deadlift"].firstMatch
        exerciseCard.press(forDuration: 1.0)
        let thisHurts = app.buttons["This hurts"]
        XCTAssertTrue(thisHurts.waitForExistence(timeout: 5))
        thisHurts.tap()
        XCTAssertTrue(app.navigationBars["This hurts"].waitForExistence(timeout: 5))

        // Drag the severity slider toward the severe end, then report.
        let slider = app.sliders.firstMatch
        if slider.waitForExistence(timeout: 5) {
            slider.adjust(toNormalizedSliderPosition: 0.95)
        }
        attach("pain-01-report-form-severe")
        app.buttons["Report"].tap()
        XCTAssertTrue(app.staticTexts["Stop this exercise"].waitForExistence(timeout: 5))
        attach("pain-02-severe-outcome")
        app.buttons["Close"].tap()

        // Trainer report — football/pain/pauses/travel sections.
        app.buttons["More"].tap()
        app.buttons["Trainer Program"].tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 10))
        let reportButton = app.buttons["Send Report to Trainer"]
        XCTAssertTrue(reportButton.waitForExistence(timeout: 5))
        reportButton.tap()
        XCTAssertTrue(app.navigationBars["Report to Trainer"].waitForExistence(timeout: 10))
        attach("report-01-supplemental-sections")
    }
}

// MARK: - PauseTravelPainUITestSeedArguments

/// Mirrors `PauseTravelPainUITestSeed`'s launch arguments (DEBUG-only
/// app-side type, not visible to this black-box UI test target) — same
/// pattern as `GuidedRunUITestSeedArguments` in `GuidedRunFlowTests.swift`.
private enum PauseTravelPainUITestSeedArguments {
    static let pauseActive = "--uitesting-pause-active"
    static let travelPain = "--uitesting-travel-pain"
}
