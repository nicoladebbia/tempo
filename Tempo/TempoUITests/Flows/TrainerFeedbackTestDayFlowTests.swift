//
// TrainerFeedbackTestDayFlowTests.swift
// Tempo
//
// trainer-feedback-tests — screenshots the two new flows end to end via the
// same DEBUG-sample convention TrainerProgramFlowTests/
// WeeklyTrainerProgramFlowTests already use (AI structuring needs a
// signed-in session, not available in this UI-test run):
//   1. "Trainer sent changes" — the paste/screenshot input screen, then the
//      diff review screen (DEBUG "Load Sample Changes" resolves fixture
//      edits against the just-imported sample program, exactly like a real
//      AI reply would).
//   2. Test-day detection — importing the DEBUG "Test Day Sample" (a single
//      5RM-test exercise pinned to today's weekday) and starting the
//      workout shows the "TEST — WORK UP TO A MAX" banner. The post-test
//      "New max" message itself (TrainingViewModel.persistCompletion /
//      TrainerTestResultMessage) is covered by TrainerTestResultTests
//      (unit, no AI/UI needed) rather than a blind numeric-entry UI script
//      here.
//

import XCTest

final class TrainerFeedbackTestDayFlowTests: XCTestCase {
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

    private func openTrainerProgram() {
        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
        app.buttons["More"].tap()
        let trainerProgramItem = app.buttons["Trainer Program"]
        XCTAssertTrue(trainerProgramItem.waitForExistence(timeout: 10))
        trainerProgramItem.tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 10))
    }

    /// A prior run's test-day workout (started but never finished, e.g. an
    /// earlier failed/interrupted UI test) leaves the active-workout cover
    /// showing — a fresh `launch()` on this shared simulator brings the
    /// still-running app back to the SAME paused session rather than a
    /// clean Today screen, which blocks every "tap the Training tab" flow
    /// below. Discard it first so each test starts from a known state,
    /// exactly like the athlete's own "End Workout -> Discard" escape hatch.
    private func dismissStuckWorkoutIfPresent() {
        // Tried a few times: an active session can show any of several
        // screens (paused overlay, live exercise/warm-up screen, the
        // crash-recovery interstitial), and dismissing one can land on
        // another (e.g. the crash prompt's "Resume" was tapped by a stale
        // reference) before the tab bar is finally reachable.
        for _ in 0 ..< 4 {
            if app.tabBars.firstMatch.waitForExistence(timeout: 2) {
                return
            }
            // Crash-recovery prompt ("It looks like a workout was in
            // progress.") — its own one-tap "Discard", no confirmation alert.
            let crashDiscard = app.buttons["Discard"]
            if crashDiscard.waitForExistence(timeout: 2) {
                crashDiscard.tap()
                continue
            }
            // A live exercise/warm-up screen ("Finish", toolbar) or the
            // paused overlay ("End Workout") both open the same
            // confirmation alert.
            let endWorkout = app.buttons["End Workout"]
            let finish = app.buttons["Finish"]
            if endWorkout.waitForExistence(timeout: 2) || finish.waitForExistence(timeout: 2) {
                (endWorkout.exists ? endWorkout : finish).tap()
                let discardWorkout = app.buttons["Discard workout"]
                if discardWorkout.waitForExistence(timeout: 5) {
                    discardWorkout.tap()
                }
                continue
            }
            // Nothing recognized — stop looping; the caller's own
            // assertions will surface whatever's actually on screen.
            break
        }
    }

    // MARK: - "Trainer sent changes" — input + diff review

    func testTrainerFeedbackInputAndReviewScreens() {
        app.launchForTesting()
        dismissStuckWorkoutIfPresent()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        openTrainerProgram()

        // A leftover program from a prior run on this simulator is fine —
        // importing again always deactivates/replaces whatever was active
        // (TrainerProgramSaver.save), so this never needs an explicit clear.
        let emptyStateImport = app.buttons["Import from Trainer"]
        let toolbarImport = app.buttons["Import from trainer"]
        XCTAssertTrue(emptyStateImport.waitForExistence(timeout: 5) || toolbarImport.waitForExistence(timeout: 5))
        (emptyStateImport.exists ? emptyStateImport : toolbarImport).tap()
        XCTAssertTrue(app.navigationBars["Import from Trainer"].waitForExistence(timeout: 10))

        let sampleButton = app.buttons["Load Sample Program (DEBUG)"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()
        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 10))
        app.navigationBars["Review Program"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 15))

        let feedbackButton = app.buttons["Trainer Sent Changes"]
        XCTAssertTrue(feedbackButton.waitForExistence(timeout: 10))
        feedbackButton.tap()
        XCTAssertTrue(app.navigationBars["Trainer Sent Changes"].waitForExistence(timeout: 10))
        attach("feedback-01-input-screen")

        let sampleChangesButton = app.buttons["Load Sample Changes (DEBUG)"]
        XCTAssertTrue(sampleChangesButton.waitForExistence(timeout: 5))
        sampleChangesButton.tap()
        XCTAssertTrue(app.navigationBars["Review Changes"].waitForExistence(timeout: 10))
        // Matched edits ("RDL" isn't in the sample -> unmatched; the
        // Thursday sprint skip and the Leg Press removal both match) plus
        // the "COULDN'T MATCH" section in one frame.
        attach("feedback-02-diff-review-screen")
    }

    // MARK: - Test-day workout banner

    func testTestDayWorkoutBanner() {
        app.launchForTesting()
        dismissStuckWorkoutIfPresent()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        openTrainerProgram()

        let emptyStateImport = app.buttons["Import from Trainer"]
        let toolbarImport = app.buttons["Import from trainer"]
        XCTAssertTrue(emptyStateImport.waitForExistence(timeout: 5) || toolbarImport.waitForExistence(timeout: 5))
        (emptyStateImport.exists ? emptyStateImport : toolbarImport).tap()
        XCTAssertTrue(app.navigationBars["Import from Trainer"].waitForExistence(timeout: 10))

        let testSampleButton = app.buttons["Load Test Day Sample (DEBUG)"]
        XCTAssertTrue(testSampleButton.waitForExistence(timeout: 5))
        testSampleButton.tap()
        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 10))
        attach("testday-01-review-program")
        app.navigationBars["Review Program"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 15))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        let startButton = app.buttons["START WORKOUT"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "today's plan should now be the test-day session")
        startButton.tap()

        // A gym workout always opens on the guided warm-up first
        // (TrainingViewModel.startWorkout) — both "Skip whole warm-up" (any
        // move) and "Start Working Sets" (the routine's last move) call the
        // same `advancePastWarmup()` straight to the exercise screen where
        // the test banner lives; only the first move's control is
        // guaranteed to be on screen without waiting out several
        // real-time move timers.
        let skipWholeWarmup = app.buttons["Skip whole warm-up"]
        let startWorkingSets = app.buttons["Start Working Sets"]
        if skipWholeWarmup.waitForExistence(timeout: 10) {
            skipWholeWarmup.tap()
        } else if startWorkingSets.waitForExistence(timeout: 2) {
            startWorkingSets.tap()
        }

        XCTAssertTrue(app.staticTexts["TEST — WORK UP TO A MAX"].waitForExistence(timeout: 10))
        attach("testday-02-workout-test-banner")
    }
}
