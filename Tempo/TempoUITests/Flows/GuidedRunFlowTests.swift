//
// GuidedRunFlowTests.swift
// Tempo
//
// Guided run mode — drives a full guided-run session from the Training
// tab's trainer card: pre-start -> countdown -> work -> rest -> summary,
// screenshotting each stage. Launches with GuidedRunUITestSeed's fixture
// (an active Anaerobic Run program pinned to today, since a UI test can't
// sign in to reach the real AI-import flow — see that file's header) and a
// modest time scale so the countdown/rest don't need real minutes, only a
// few real seconds.
//

import XCTest

// MARK: - GuidedRunFlowTests

final class GuidedRunFlowTests: XCTestCase {
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

    /// SwiftUI's accessibility bridging doesn't guarantee a combined
    /// `.accessibilityElement(children: .combine)` view surfaces as
    /// `XCUIElementTypeOther` — matching by identifier across ANY element
    /// type is the robust way to find it regardless.
    private func element(id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testGuidedRunFromTrainerCardThroughSummary() {
        // Scale 1 (a no-op multiplier) exercises the same
        // --uitesting-time-scale launch-argument path a slower fixture
        // would need, without racing this test's own polling: the seed's
        // rest is already short (5s, see GuidedRunUITestSeed) and this
        // fixture has no continuous duration/distance step that would
        // otherwise wait out real minutes.
        app.launchForTesting(extraArguments: [
            GuidedRunUITestSeedArguments.sample,
            "--uitesting-time-scale=1",
        ])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()

        let startButton = app.buttons["startGuidedRunButton"]
        var found = startButton.waitForExistence(timeout: 15)
        // The trainer card may render below the fold on a non-gym day —
        // a few swipes bring it into the accessibility tree's visible area.
        var attempts = 0
        while !found, attempts < 6 {
            app.swipeUp()
            found = startButton.waitForExistence(timeout: 2)
            attempts += 1
        }
        XCTAssertTrue(found, "expected the trainer card's Start guided run button")
        attach("01-trainer-card")
        startButton.tap()

        // Pre-start screen.
        let startSessionButton = app.buttons["guidedRunStartSessionButton"]
        XCTAssertTrue(startSessionButton.waitForExistence(timeout: 10))
        attach("02-pre-start")
        startSessionButton.tap()

        // Countdown — 3 real seconds (this fixture launches at time-scale 1).
        XCTAssertTrue(element(id: "guidedRunCountdownScreen").waitForExistence(timeout: 8))
        attach("03-countdown")

        // Work: first shuttle rep.
        let doneButton = app.buttons["guidedRunDoneButton"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 10))
        attach("04-work")
        doneButton.tap()

        // Rest between reps.
        XCTAssertTrue(element(id: "guidedRunRestScreen").waitForExistence(timeout: 10))
        attach("05-rest")

        // Skip through the remaining reps/rest/blocks straight to the
        // summary — the test only needs one of each screen kind, not a
        // full session.
        let skipRestButton = app.buttons["guidedRunSkipRestButton"]
        if skipRestButton.waitForExistence(timeout: 5) {
            skipRestButton.tap()
        }
        for _ in 0 ..< 12 {
            if app.buttons["guidedRunSaveButton"].exists {
                break
            }
            if doneButton.waitForExistence(timeout: 3) {
                doneButton.tap()
            } else if skipRestButton.waitForExistence(timeout: 3) {
                skipRestButton.tap()
            }
        }

        let saveButton = app.buttons["guidedRunSaveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 15))
        attach("06-summary")
        saveButton.tap()

        // Saving dismisses the guided run screen back to Today.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }
}

// MARK: - GuidedRunUITestSeedArguments

/// Mirrors GuidedRunUITestSeed.launchArgument (DEBUG-only app-side type,
/// not linked into the UI test target) so this test doesn't hardcode the
/// raw string in two places.
private enum GuidedRunUITestSeedArguments {
    static let sample = "--uitesting-guided-run-sample"
}
