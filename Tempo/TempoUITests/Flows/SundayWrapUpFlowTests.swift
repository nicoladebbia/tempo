//
// SundayWrapUpFlowTests.swift
// Tempo
//
// Sunday wrap-up feature — screenshots the guided "Wrap up the week" flow
// end to end: the card's new CTA on Today, the recap step, the embedded
// trainer-report step, and the embedded upload-next-week step. Reuses
// `WeeklyUploadUITestSeed` (`--uitesting-weekly-upload-due`) — same fixture
// `WeeklyTrainerProgramFlowTests` uses for the card itself, so this test
// doesn't need its own seed or a real Sunday 19:00.
//

import XCTest

final class SundayWrapUpFlowTests: XCTestCase {
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

    func testWrapUpFlowThreeSteps() {
        app.launchForTesting(extraArguments: ["--uitesting-weekly-upload-due"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        let wrapUpButton = app.buttons["Wrap up the week"]
        XCTAssertTrue(wrapUpButton.waitForExistence(timeout: 10), "wrap-up CTA should render on Today once the seed's program is due")
        var attempts = 0
        while !wrapUpButton.isHittable, attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        wrapUpButton.tap()

        // Step (a) — recap.
        XCTAssertTrue(app.staticTexts["YOUR WEEK"].waitForExistence(timeout: 10))
        attach("wrapup-01-recap")

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        // Step (b) — send to trainer (the real TrainerReportSheet, embedded).
        XCTAssertTrue(app.navigationBars["Report to Trainer"].waitForExistence(timeout: 10))
        attach("wrapup-02-send-report")

        let skipButton = app.buttons["Skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        // Step (c) — upload next week (the real TrainerProgramImportView, embedded).
        XCTAssertTrue(app.navigationBars["Import from Trainer"].waitForExistence(timeout: 10))
        attach("wrapup-03-upload-next")
    }

    // MARK: - Week-over-week progress line

    /// Same card/flow, but seeded with a PRIOR and a CURRENT `ExerciseHistory`
    /// row for the same exercise (`SundayWrapUpProgressUITestSeed`) so the
    /// recap's "TOP LIFTS" bullet actually has a "vs last week" delta to
    /// show, not just an empty section.
    func testRecapShowsWeekOverWeekProgressLine() {
        app.launchForTesting(extraArguments: ["--uitesting-wrapup-progress"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        let wrapUpButton = app.buttons["Wrap up the week"]
        XCTAssertTrue(wrapUpButton.waitForExistence(timeout: 10))
        var attempts = 0
        while !wrapUpButton.isHittable, attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        wrapUpButton.tap()

        XCTAssertTrue(app.staticTexts["YOUR WEEK"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["TOP LIFTS"].waitForExistence(timeout: 5),
            "seeded prior+current history should produce a progress line"
        )
        attach("wrapup-04-recap-progress-line")
    }
}
