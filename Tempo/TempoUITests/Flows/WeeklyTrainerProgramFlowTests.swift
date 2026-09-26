//
// WeeklyTrainerProgramFlowTests.swift
// Tempo
//
// Weekly-upload feature — screenshots the new UI end to end: the cadence
// picker on the review screen, the active-card duration text for a weekly
// AND a block program, the "New week — upload" card (via
// WeeklyUploadUITestSeed — waiting for a real Sunday 19:00 isn't practical
// in a UI test), and the bedtime card's new "Skip for tonight" button
// (via a TZ launch-environment override so LateNightWindow's real-clock
// check reads as after-midnight regardless of when this actually runs — a
// manual/CI verification aid, same spirit as ExerciseImagesScreenshotTests).
//

import XCTest

final class WeeklyTrainerProgramFlowTests: XCTestCase {
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

    // MARK: - Review picker + weekly/block active-card duration text

    func testCadencePickerAndActiveCardDurationText() {
        app.launchForTesting()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))

        app.buttons["More"].tap()
        let trainerProgramItem = app.buttons["Trainer Program"]
        XCTAssertTrue(trainerProgramItem.waitForExistence(timeout: 5))
        trainerProgramItem.tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 10))

        // Empty state ("Import from Trainer") vs an already-active program's
        // toolbar (+) button ("Import from trainer") — same dual-lookup
        // TrainerProgramFix6FlowTests uses, so a rerun on a non-fresh
        // simulator still finds its way in.
        let emptyStateImport = app.buttons["Import from Trainer"]
        let toolbarImport = app.buttons["Import from trainer"]
        XCTAssertTrue(emptyStateImport.waitForExistence(timeout: 5) || toolbarImport.waitForExistence(timeout: 5))
        (emptyStateImport.exists ? emptyStateImport : toolbarImport).tap()
        XCTAssertTrue(app.navigationBars["Import from Trainer"].waitForExistence(timeout: 10))

        let sampleButton = app.buttons["Load Sample Program (DEBUG)"]
        XCTAssertTrue(sampleButton.waitForExistence(timeout: 5))
        sampleButton.tap()
        XCTAssertTrue(app.navigationBars["Review Program"].waitForExistence(timeout: 10))

        // The sample is a single week — pre-selects "A new program every
        // week". This is the "How does your trainer send programs?" picker.
        attach("weekly-01-review-cadence-picker")

        app.navigationBars["Review Program"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 15))
        attach("weekly-02-active-card-weekly")

        // Switch cadence to a block via Edit, to also capture the block
        // duration text ("Week X of N ..." / "N-week block · repeats") on
        // the same active card.
        let editButton = app.buttons["Edit"]
        guard editButton.waitForExistence(timeout: 5) else {
            return
        }
        editButton.tap()
        XCTAssertTrue(app.navigationBars["Edit Program"].waitForExistence(timeout: 10))

        // The cadence row merges label + current value into one Button
        // (e.g. "How does your trainer send programs?, A new program every
        // week") — matched by a BEGINSWITH predicate, not an exact label.
        let cadenceRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "How does your trainer send programs?")
        ).firstMatch
        if cadenceRow.waitForExistence(timeout: 5) {
            cadenceRow.tap()
            let blockOption = app.buttons["A block of weeks"]
            if blockOption.waitForExistence(timeout: 5) {
                blockOption.tap()
                // Selecting a Form Picker's option auto-pops back to "Edit
                // Program" — no separate back-button tap needed (an extra
                // one here would hit "Cancel" and discard the whole edit).
                _ = app.navigationBars["Edit Program"].waitForExistence(timeout: 5)
            }
        }
        app.navigationBars["Edit Program"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Trainer Program"].waitForExistence(timeout: 15))
        // Give the sheet-dismiss animation a beat to settle before the
        // screenshot, so it doesn't catch a mid-transition frame.
        _ = app.staticTexts["ACTIVE"].waitForExistence(timeout: 5)
        attach("weekly-03-active-card-block")
    }

    // MARK: - "New week — upload" card

    func testWeeklyUploadPromptCardOnToday() {
        app.launchForTesting(extraArguments: ["--uitesting-weekly-upload-due"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
        // The card sits below the day's own session content (same position
        // as MissedTrainerSessionCard). Today's whole VStack renders eagerly
        // inside the ScrollView, so the label already `exists` off-screen —
        // scroll by `isHittable` (on-screen), not mere existence.
        let cardLabel = app.staticTexts["NEW WEEK"]
        XCTAssertTrue(cardLabel.waitForExistence(timeout: 5), "card should render somewhere on Today")
        var attempts = 0
        while !cardLabel.isHittable, attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        attach("weekly-04-upload-prompt-card")
    }

    // MARK: - Bedtime card "Skip for tonight"

    /// A fixed-offset (no-DST) timezone that maps whatever real UTC instant
    /// this runs at into local hour ~2am — comfortably inside
    /// `LateNightWindow`'s 00:00–05:00 window, without touching the host
    /// Mac's own clock.
    private func lateNightTimeZoneIdentifier() -> String {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let utcHour = utcCalendar.component(.hour, from: Date())
        var offset = (2 - utcHour) % 24
        if offset > 12 {
            offset -= 24
        }
        if offset < -12 {
            offset += 24
        }
        if offset == 0 {
            return "Etc/GMT"
        }
        // POSIX Etc/GMT signs are inverted: Etc/GMT-9 means UTC+9.
        return offset > 0 ? "Etc/GMT-\(offset)" : "Etc/GMT+\(-offset)"
    }

    func testBedtimeCardSkipForTonightButton() {
        app.launchEnvironment["TZ"] = lateNightTimeZoneIdentifier()
        // The TZ override can shift "today" onto a different calendar date
        // than mock data's own schedule expects (it landed on a rest day in
        // an earlier run) — GuidedRunUITestSeed pins an active trainer
        // session to TODAY'S weekday regardless, guaranteeing a trainable
        // day so the bedtime card has something to preview.
        app.launchForTesting(extraArguments: ["--uitesting-late-night", "--uitesting-guided-run-sample"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        app.tabBars.buttons["Training"].tap()
        XCTAssertTrue(app.navigationBars["Training"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["It's past midnight. Get to bed."].waitForExistence(timeout: 10))
        attach("weekly-05-bedtime-card-skip-for-tonight")
    }
}
