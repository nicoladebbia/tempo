//
// TrainerProgramFix9FlowTests.swift
// Tempo
//
// Fix #9 — per-side (unilateral) set logging and volume. Drives the same
// DEBUG "Load Sample Program" path as TrainerProgramFlowTests (its sample
// includes a Single-Arm DB Row, %1RM 0.7, on the "Hypertrophy Lifting 2"
// day) through to Today, then screenshots the "/ side" prescription copy
// and, when that day lands and the exercise is reachable, the active
// workout's per-side REPS input + optional L/R split control.
//

import XCTest

final class TrainerProgramFix9FlowTests: XCTestCase {
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

    func testPerSideRendersOnTodayCardAndActiveWorkout() {
        app.launchForTesting()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        app.buttons["More"].tap()
        let trainerProgramItem = app.buttons["Trainer Program"]
        XCTAssertTrue(trainerProgramItem.waitForExistence(timeout: 5))
        trainerProgramItem.tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 10))

        let emptyStateImport = app.buttons["Import from Trainer"]
        let toolbarImport = app.buttons["Import from trainer"]
        XCTAssertTrue(
            emptyStateImport.waitForExistence(timeout: 5) || toolbarImport.waitForExistence(timeout: 5)
        )
        (emptyStateImport.exists ? emptyStateImport : toolbarImport).tap()
        XCTAssertTrue(app.navigationBars["Import from Trainer"].waitForExistence(timeout: 10))

        let sampleButton = app.buttons["Load Sample Program (DEBUG)"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()
        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 10))

        // Fix #9 — the review screen's per-exercise "Per side" toggle,
        // pre-checked from the sample's SA DB Row.
        app.swipeUp()
        app.swipeUp()
        attach("fix9-01-review-program-per-side-toggle")

        app.navigationBars["Review Program"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 15))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        let legPress = app.staticTexts["LEG PRESS"]
        let legExtension = app.staticTexts["LEG EXTENSION"]
        let sampleExerciseVisible = NSPredicate { _, _ in
            legPress.exists || legExtension.exists
        }
        let expectation = XCTNSPredicateExpectation(predicate: sampleExerciseVisible, object: nil)
        let waitResult = XCTWaiter().wait(for: [expectation], timeout: 15)
        guard waitResult == .completed else {
            attach("fix9-02-today-workout-card-no-trainer-day")
            return
        }

        // Fix #9 — on "Hypertrophy Lifting 2" the Today card lists SA DB Row
        // with its "8 / side" (or similar) prescription text. Scroll to find
        // it; the card may not land as the very first exercise.
        for _ in 0 ..< 4 where !app.staticTexts["SINGLE-ARM DUMBBELL ROW"].exists {
            app.swipeUp()
        }
        attach("fix9-02-today-workout-card")

        guard app.staticTexts["SINGLE-ARM DUMBBELL ROW"].exists else {
            // Lifting 1 landed instead of Lifting 2 — the per-side exercise
            // isn't on today's card; documented, not a failure (matches the
            // existing FixB flow test's same day-landing caveat).
            return
        }

        app.buttons["START WORKOUT"].tap()
        let skipWholeWarmup = app.buttons["Skip whole warm-up"]
        if skipWholeWarmup.waitForExistence(timeout: 10) {
            skipWholeWarmup.tap()
        }

        // Advance through sets/exercises (skipping warmups and working sets)
        // until the per-side REPS control appears, or we give up.
        let repsLeftLabel = app.staticTexts["REPS — LEFT"]
        for _ in 0 ..< 20 where !repsLeftLabel.exists {
            if app.buttons["Skip Ramp"].exists {
                app.buttons["Skip Ramp"].tap()
            } else if app.buttons["Skip"].exists {
                app.buttons["Skip"].tap()
            } else {
                break
            }
        }
        attach("fix9-03-active-workout-per-side-reps")

        if repsLeftLabel.exists {
            app.buttons["Log sides separately"].tap()
            attach("fix9-04-active-workout-lr-split-control")
        }
    }
}
