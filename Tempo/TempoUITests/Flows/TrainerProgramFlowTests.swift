//
// TrainerProgramFlowTests.swift
// Tempo
//
// Drives the Trainer Program import flow end to end in the simulator: the
// Training tab's ☰ menu -> Trainer Program (empty state) -> Import ->
// DEBUG "Load Sample Program" -> the review screen. AI structuring needs a
// signed-in session (not available in this UI-test run), so this exercises
// the review/save UI via the DEBUG sample path per CLAUDE.md's verification
// note. Attaches a screenshot at each stage for manual/CI inspection.
//

import XCTest

final class TrainerProgramFlowTests: XCTestCase {
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

    func testImportFlowReachesReviewScreenViaDebugSample() {
        app.launchForTesting()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        app.buttons["More"].tap()
        let trainerProgramItem = app.buttons["Trainer Program"]
        XCTAssertTrue(trainerProgramItem.waitForExistence(timeout: 5))
        trainerProgramItem.tap()

        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 10))
        attach("01-trainer-program-empty-state")

        let importButton = app.buttons["Import from Trainer"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()

        XCTAssertTrue(app.navigationBars["Import from Trainer"].waitForExistence(timeout: 10))
        attach("02-import-source-picker")

        let sampleButton = app.buttons["Load Sample Program (DEBUG)"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()

        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 10))
        attach("03-review-program")
    }
}
