//
// ExerciseImagesScreenshotTests.swift
// Tempo
//
// One-off screenshot capture for feat/exercise-images — no OPENAI_API_KEY is
// configured, so every ExerciseImageView shows its equipment-icon
// placeholder; this pins that the placeholder state renders cleanly (no
// broken layout, no crash) in the three places the feature was added:
// Today's exercise list, the active workout hero, and the exercise library.
// Not meant to be a permanent regression test — a manual verification aid.
//

import XCTest

final class ExerciseImagesScreenshotTests: XCTestCase {
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

    func testExerciseImagePlaceholdersAcrossTodayActiveWorkoutAndLibrary() {
        app.launchForTesting()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
        attach("01-today-with-thumbnails")

        let startButton = app.buttons["START WORKOUT"]
        if startButton.waitForExistence(timeout: 5) {
            startButton.tap()
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 10)
            attach("02-active-workout-hero")
        } else {
            attach("02-active-workout-hero-NO-START-BUTTON")
        }
    }

    func testExerciseLibraryThumbnails() {
        app.launchForTesting()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        app.buttons["More"].tap()
        let libraryItem = app.buttons["Exercise Library"]
        XCTAssertTrue(libraryItem.waitForExistence(timeout: 5))
        libraryItem.tap()

        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 10)
        attach("03-exercise-library-thumbnails")
    }

    /// Mock data's seeded schedule puts today (a real calendar Friday) on a
    /// swim/conditioning day with no lifting exercises, so Today's list and
    /// the active-workout hero can't be reached live this run (see the
    /// other test's "-NO-START-BUTTON" fallback). This exercises the same
    /// ExerciseImageView(style: .thumbnail) call site in a real list of
    /// exercises via the DEBUG sample Trainer Program import (mirrors
    /// TrainerProgramFlowTests) as the closest available stand-in for
    /// placement (b)/(d).
    func testTrainerProgramReviewThumbnails() {
        app.launchForTesting()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        app.buttons["More"].tap()
        let trainerProgramItem = app.buttons["Trainer Program"]
        XCTAssertTrue(trainerProgramItem.waitForExistence(timeout: 5))
        trainerProgramItem.tap()

        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 10))
        let importButton = app.buttons["Import from Trainer"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()

        XCTAssertTrue(app.navigationBars["Import from Trainer"].waitForExistence(timeout: 10))
        let sampleButton = app.buttons["Load Sample Program (DEBUG)"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()

        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 10))

        let firstDay = app.staticTexts["Mon — Hypertrophy Lifting 1"]
        if firstDay.waitForExistence(timeout: 5) {
            firstDay.tap()
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 5)
        }
        attach("04-trainer-review-day-thumbnails")
    }
}
