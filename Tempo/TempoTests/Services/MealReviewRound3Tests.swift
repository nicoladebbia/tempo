//
// MealReviewRound3Tests.swift
// Tempo
//
// Nutrition round 3, lane B: Quick Log time parsing, the review draft
// (portion scaling, time → meal type), stable sheet identity (the photo
// "other guesses" sheet used to dismiss itself in a loop), photo-row
// corrections, and the scanner's mode memory.
//

@testable import Tempo
import XCTest

final class MealReviewRound3Tests: XCTestCase {
    private let calendar = Calendar.current

    /// 2026-10-02 15:00 local.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 15, minute: 0))!
    }

    private func clock(_ date: Date?) -> (day: Int, hour: Int, minute: Int)? {
        date.map {
            (calendar.component(.day, from: $0), calendar.component(.hour, from: $0), calendar.component(.minute, from: $0))
        }
    }

    private func food(_ id: String, grams: Double = 200, kcal: Double = 260) -> ParsedFoodItem {
        ParsedFoodItem(
            id: id, name: "cooked rice", quantityGrams: grams, calories: kcal,
            proteinG: 5, carbsG: 56, fatG: 1, isVerified: false
        )
    }

    // MARK: - Time parsing

    func testAtOnePmParsesToToday1300() throws {
        let hints = MealTimeHints.parse("chicken bowl at 1pm", now: now, calendar: calendar)
        let parts = try XCTUnwrap(clock(hints.date))
        XCTAssertEqual(parts.day, 2)
        XCTAssertEqual(parts.hour, 13)
        XCTAssertEqual(parts.minute, 0)
        XCTAssertNil(hints.mealType)
    }

    func testTwentyFourHourClock() throws {
        let parts = try XCTUnwrap(clock(MealTimeHints.parse("pasta at 13:30", now: now, calendar: calendar).date))
        XCTAssertEqual(parts.hour, 13)
        XCTAssertEqual(parts.minute, 30)
    }

    func testForLunchSetsTypeButKeepsNow() {
        let hints = MealTimeHints.parse("a wrap for lunch", now: now, calendar: calendar)
        XCTAssertEqual(hints.mealType, .lunch)
        XCTAssertNil(hints.date)
    }

    func testYesterdayDinnerUsesYesterdayEvening() throws {
        let hints = MealTimeHints.parse("yesterday dinner: steak and fries", now: now, calendar: calendar)
        let parts = try XCTUnwrap(clock(hints.date))
        XCTAssertEqual(parts.day, 1)
        XCTAssertEqual(parts.hour, 20)
        XCTAssertEqual(hints.mealType, .dinner)
    }

    func testDinnerAtEightResolvesToEvening() throws {
        let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 22))!
        let hints = MealTimeHints.parse("dinner at 8", now: late, calendar: calendar)
        XCTAssertEqual(clock(hints.date)?.hour, 20)
    }

    func testPlainFoodTextHasNoTimeNorType() {
        for text in ["200g chicken and 2 eggs", "3 slices of toast with 15g butter", "i ate a chicken kitchen bowl"] {
            XCTAssertEqual(MealTimeHints.parse(text, now: now, calendar: calendar), .none, text)
        }
    }

    func testAmPmEdgeCases() {
        XCTAssertEqual(clock(MealTimeHints.parse("coffee at 12am", now: now, calendar: calendar).date)?.hour, 0)
        XCTAssertEqual(clock(MealTimeHints.parse("toast at 7:15 am", now: now, calendar: calendar).date)?.hour, 7)
        XCTAssertEqual(clock(MealTimeHints.parse("salad at 12pm", now: now, calendar: calendar).date)?.hour, 12)
    }

    func testQuantitiesAndEdgeTimesAreNotMisreadAsClock() throws {
        XCTAssertNil(MealTimeHints.parse("ate around 3 eggs", now: now, calendar: calendar).date)
        XCTAssertEqual(clock(MealTimeHints.parse("lunch at 12", now: now, calendar: calendar).date)?.hour, 12)
        // Future time today means just now, never a future-dated meal.
        let early = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))!
        XCTAssertEqual(MealTimeHints.parse("pasta at 1pm", now: early, calendar: calendar).date, early)
    }

    // MARK: - Portion scaling

    func testScaleHalfHalvesGramsAndMacros() {
        let half = food("a").scaled(by: 0.5)
        XCTAssertEqual(half.quantityGrams, 100)
        XCTAssertEqual(half.calories, 130)
        XCTAssertEqual(half.carbsG, 28)
    }

    func testScaleToGramsAndUnknownWeight() {
        XCTAssertEqual(food("a").scaled(toGrams: 300).calories, 390)
        let unknown = food("b", grams: 0)
        XCTAssertEqual(unknown.scaled(toGrams: 300).calories, 260)
    }

    func testDraftChipsGramsAndRemove() {
        var draft = MealReviewDraft(items: [food("a"), food("b", grams: 100, kcal: 100)], now: now)
        XCTAssertEqual(draft.totalCalories, 360)
        draft.setFactor(1.5, for: "a")
        XCTAssertEqual(draft.totalCalories, 490)
        draft.setGrams(400, for: "a")
        XCTAssertEqual(draft.factor(for: "a"), 2, accuracy: 0.001)
        draft.setGrams(100_000, for: "a")
        XCTAssertEqual(draft.factor(for: "a"), MealReviewDraft.maxFactor)
        draft.remove("a")
        XCTAssertEqual(draft.items.map(\.id), ["b"])
        XCTAssertEqual(draft.totalCalories, 100)
    }

    // MARK: - Time drives meal type

    func testMealTypeFollowsTheChosenTime() throws {
        var draft = MealReviewDraft(items: [food("a")], now: now) // 15:00 -> lunch
        XCTAssertEqual(draft.mealType, .lunch)
        draft.setEatenAt(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 20, minute: 30))!)
        XCTAssertEqual(draft.mealType, .dinner)
        draft.setMealType(.snack)
        XCTAssertEqual(draft.mealType, .snack, "a manual pick sticks until the time moves")
        draft.setEatenAt(calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 8))!)
        XCTAssertEqual(draft.mealType, .breakfast)
    }

    func testHintsWinOverNow() {
        let draft = MealReviewDraft(items: [food("a")], hintedDate: now.addingTimeInterval(-7200), hintedType: .breakfast, now: now)
        XCTAssertEqual(draft.mealType, .breakfast)
        XCTAssertEqual(draft.eatenAt, now.addingTimeInterval(-7200))
    }

    // MARK: - Sheet identity (the open-close loop)

    func testReviewPayloadIdentityIsStableAcrossReads() {
        let items = [food("a"), food("b")]
        XCTAssertEqual(ParsedFoodReviewPayload(items: items).id, ParsedFoodReviewPayload(items: items).id)
        XCTAssertNotEqual(ParsedFoodReviewPayload(items: items).id, ParsedFoodReviewPayload(items: [food("c")]).id)
    }

    func testAlternativesPayloadIdentityIsTheRowId() {
        let item = analyzed()
        let first = AlternativesSheetPayload(itemID: item.id, item: item)
        let second = AlternativesSheetPayload(itemID: item.id, item: item)
        XCTAssertEqual(first.id, second.id, "a new id per read made the sheet dismiss and re-present forever")
        XCTAssertEqual(first.id, item.id)
    }

    // MARK: - Photo row corrections

    private func candidate(_ name: String, kcal: Double = 215, confidence: Double = 0.55) -> PhotoAnalysisResult.FoodCandidate {
        PhotoAnalysisResult.FoodCandidate(
            id: name, name: name, estimatedPortion: "150g", calories: kcal,
            proteinGrams: 39, carbsGrams: 0, fatGrams: 5, confidence: confidence
        )
    }

    private func analyzed(score: Double = 0.45) -> AnalyzedFoodItem {
        AnalyzedFoodItem(
            id: UUID(), name: "Mystery meat", estimatedPortion: "150g", calories: 300,
            protein: 30, carbs: 0, fat: 10, score: score, servingMultiplier: 1,
            alternatives: [candidate("Tofu scramble")]
        )
    }

    func testLowConfidenceAsksAndAnswerConfirms() {
        var item = analyzed()
        XCTAssertTrue(item.needsQuestion)
        XCTAssertEqual(item.clarifyingQuestion, "Is this mystery meat or tofu scramble?")
        item.confirm()
        XCTAssertFalse(item.needsQuestion)
    }

    func testSwapKeepsPreviousAsAlternativeAndConfirms() {
        let item = analyzed()
        let swapped = item.applying(candidate("Tofu scramble"))
        XCTAssertEqual(swapped.name, "Tofu scramble")
        XCTAssertEqual(swapped.id, item.id)
        XCTAssertEqual(swapped.alternatives.first?.name, "Mystery meat")
        XCTAssertFalse(swapped.needsQuestion)
    }

    func testRenameReverifiesAgainstFoodTable() {
        let item = analyzed().renamed(to: "chicken breast")
        XCTAssertTrue(item.isVerified)
        XCTAssertEqual(item.calories, 248) // 165 kcal/100g x 150g
        XCTAssertEqual(item.name, "chicken breast")
    }

    func testRenameToUnknownFoodKeepsEstimate() {
        let item = analyzed().renamed(to: "zzqx special")
        XCTAssertFalse(item.isVerified)
        XCTAssertEqual(item.calories, 300)
        XCTAssertLessThan(item.score, 0.9, "stale numbers must not claim certainty")
    }

    func testManualItem() {
        XCTAssertEqual(AnalyzedFoodItem.manual(name: "chicken breast", grams: 200, kcal: nil)?.calories, 330)
        XCTAssertNil(AnalyzedFoodItem.manual(name: "zzqx special", grams: 100, kcal: nil))
        XCTAssertEqual(AnalyzedFoodItem.manual(name: "zzqx special", grams: 100, kcal: 120)?.calories, 120)
    }

    func testServingMultiplierFlowsIntoFoodItem() {
        var item = analyzed(score: 0.9)
        item.servingMultiplier = 2
        let out = item.asFoodItem()
        XCTAssertEqual(out.calories, 600)
        XCTAssertEqual(out.servingQuantity, 2)
    }

    // MARK: - Scanner mode memory

    private func product() -> FoodProduct {
        FoodProduct(id: "123", barcode: "123", name: "Skyr", brand: nil, source: .openFoodFacts, per100g: .init(kcal: 60, protein: 11, carbs: 4, fat: 0.2))
    }

    func testScannedProductSurvivesModeSwitchesUntilScanAnother() {
        var memory = ScanModeMemory()
        XCTAssertEqual(memory.labelPage, .capture)
        memory.scannedProduct = product()
        memory.modeChanged() // Barcode -> Label
        XCTAssertEqual(memory.labelPage, .scannedLabel(product()))
        memory.modeChanged() // Label -> Barcode
        XCTAssertEqual(memory.scannedProduct, product(), "Barcode mode returns to the scanned product")
        memory.scanAnother()
        XCTAssertNil(memory.scannedProduct)
        XCTAssertEqual(memory.labelPage, .capture)
    }

    func testLabelSavedProductDoesNotOutliveLabelMode() {
        var memory = ScanModeMemory()
        memory.scannedProduct = product()
        memory.labelProduct = product()
        XCTAssertEqual(memory.labelPage, .product(product()))
        memory.modeChanged()
        XCTAssertEqual(memory.labelPage, .scannedLabel(product()))
    }
}
