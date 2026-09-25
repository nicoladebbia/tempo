//
// TrainerProgramFix6FlowTests.swift
// Tempo
//
// Screenshots the new fix #6/#11 UI end to end: the schedule-mode picker on
// the review screen, the active program screen's own Schedule picker + Edit
// button, and the edit screen reached from it. Drives the same DEBUG "Load
// Sample Program" path as TrainerProgramFlowTests/TrainerProgramFixBFlowTests.
//

import XCTest

final class TrainerProgramFix6FlowTests: XCTestCase {
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

    func testScheduleModeAndEditUIRenderEndToEnd() {
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

        // Fix #6 — the "Schedule" picker + explanation, right under the
        // Tempo warm-up sets toggle in the PROGRAM section.
        attach("fix6-01-review-schedule-mode-picker")

        app.navigationBars["Review Program"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 15))

        // Fix #6/#11 — the active program card: Schedule picker + the new
        // Edit button alongside Deactivate/Delete.
        attach("fix6-02-program-screen-schedule-and-edit")

        // Fix #11(a) — Edit reopens the review screen in edit mode.
        let editButton = app.buttons["Edit"]
        if editButton.waitForExistence(timeout: 5) {
            editButton.tap()
            XCTAssertTrue(app.navigationBars["Edit Program"].waitForExistence(timeout: 10))
            attach("fix6-03-edit-program-screen")
        }
    }
}
