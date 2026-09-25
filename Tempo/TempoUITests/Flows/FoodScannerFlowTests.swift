//
// FoodScannerFlowTests.swift
// Tempo
//
// Nutrition → Log → Check → type a barcode (the simulator has no camera) →
// real Open Food Facts lookup → the product screen with its Tempo score.
// Then an unknown barcode → "Add this product" → the add form.
// Needs network (Open Food Facts is public, no sign-in).
//

import XCTest

final class FoodScannerFlowTests: XCTestCase {
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

    private func openScanner() {
        app.launchForTesting()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        app.tabBars.buttons["Nutrition"].tap()
        let logSegment = app.segmentedControls.buttons["Log"]
        XCTAssertTrue(logSegment.waitForExistence(timeout: 10))
        logSegment.tap()

        let check = app.buttons["nutritionCheckFood"]
        XCTAssertTrue(check.waitForExistence(timeout: 10))
        check.tap()
        XCTAssertTrue(app.navigationBars["Check Food"].waitForExistence(timeout: 10))
        attach("01-check-food-hub")

        app.buttons["checkScan"].tap()
    }

    private func typeBarcode(_ code: String) {
        // Simulator: no DataScanner → "Type the barcode" empty state.
        let typeButton = app.buttons["Type the barcode"]
        XCTAssertTrue(typeButton.waitForExistence(timeout: 10))
        typeButton.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(code)
        app.alerts.buttons["Look up"].tap()
    }

    func testScanKnownProductShowsScore() {
        openScanner()
        typeBarcode("3017620422003") // Nutella 400 g

        let rating = app.staticTexts["foodScoreRating"]
        XCTAssertTrue(rating.waitForExistence(timeout: 30), "Product screen with a score")
        XCTAssertTrue(["POOR", "BAD"].contains(rating.label), "Nutella rates poor or bad, got \(rating.label)")
        XCTAssertTrue(app.staticTexts["NUTRITION"].exists || app.staticTexts["NUTRITION"].waitForExistence(timeout: 5))
        _ = app.images.firstMatch.waitForExistence(timeout: 5) // product photo loads async
        attach("02-product-score")

        app.swipeUp()
        app.swipeUp()
        attach("03-product-details")
    }

    func testUnknownBarcodeOffersAddProduct() {
        openScanner()
        // A fresh random code each run: products added by earlier runs stay
        // on the simulator, and a random one could exist in Open Food Facts —
        // if so, scan another.
        let add = app.buttons["addMissingProduct"]
        var attempts = 0
        repeat {
            attempts += 1
            if attempts > 1 {
                app.buttons["scanAnother"].tap()
            }
            typeBarcode("4000000" + String(format: "%06d", Int.random(in: 0 ..< 1_000_000)))
            let rating = app.staticTexts["foodScoreRating"]
            let notFound = add.waitForExistence(timeout: 30)
            if notFound || !rating.exists {
                break
            }
        } while attempts < 3
        XCTAssertTrue(add.exists)
        attach("04-not-found")
        add.tap()

        XCTAssertTrue(app.navigationBars["Add product"].waitForExistence(timeout: 10))
        let name = app.textFields["addProductName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test Protein Bar")
        for (id, value) in [("addProductKcal", "380"), ("addProductProtein", "30"), ("addProductCarbs", "35"), ("addProductFat", "12"), ("addProductSalt", "0.4")] {
            let field = app.textFields[id]
            if !field.isHittable {
                app.swipeUp()
            }
            field.tap()
            field.typeText(value)
        }
        attach("05-add-product-form")
        app.buttons["addProductSave"].tap()

        let rating = app.staticTexts["foodScoreRating"]
        XCTAssertTrue(rating.waitForExistence(timeout: 10), "Saved product opens with a score")
        attach("06-added-product")
    }
}
