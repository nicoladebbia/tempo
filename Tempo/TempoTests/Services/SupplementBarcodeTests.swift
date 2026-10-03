//
// SupplementBarcodeTests.swift
// Tempo
//
// UPC-A / EAN-13 / UPC-E normalisation (the likely reason supplement scans
// failed), the label-photo reader's JSON mapping, the shelf grouping that
// mirrors Today's card, the "Took it" history and the search / lookup wire
// shapes (fixture JSON from the real backend responses).
//

@testable import Tempo
import XCTest

final class SupplementBarcodeTests: XCTestCase {
    private func normalized(_ raw: String) -> SupplementBarcode? {
        if case let .success(value) = SupplementBarcode.normalize(raw) { return value }
        return nil
    }

    func testPhoneEAN13WithLeadingZeroIsTheSameAsTheUPCA() {
        let a = normalized("0748927028669")
        let b = normalized("748927028669")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a?.canonical, "748927028669")
        XCTAssertEqual(a?.variants, ["748927028669", "0748927028669"])
    }

    func testSpacesDashesAndGTIN14() {
        XCTAssertEqual(normalized("7 48927 02866 9")?.canonical, "748927028669")
        XCTAssertEqual(normalized("7-48927-02866-9")?.canonical, "748927028669")
        XCTAssertEqual(normalized("00748927028669")?.canonical, "748927028669")
    }

    func testLostLeadingZeroIsRestored() {
        // Nature Made 0 31604 02616 5.
        XCTAssertEqual(normalized("31604026165")?.canonical, "031604026165")
    }

    func testRealEAN13StaysEAN13() {
        let b = normalized("4006381333931")
        XCTAssertEqual(b?.canonical, "4006381333931")
        XCTAssertNil(b?.upcA)
    }

    func testUPCEExpands() {
        XCTAssertEqual(normalized("01234565")?.canonical, "012345000065")
    }

    func testBadCheckDigitAndLength() {
        XCTAssertEqual(SupplementBarcode.normalize("748927028660"), .failure(.badCheckDigit))
        XCTAssertEqual(SupplementBarcode.normalize("12345"), .failure(.badLength))
        XCTAssertEqual(SupplementBarcode.normalize("abc"), .failure(.badLength))
    }

    func testRealSupplementBarcodesAreValid() {
        for code in ["748927028669", "031604026165", "768990017926", "693749015116", "631656343946"] {
            XCTAssertNotNil(normalized(code), code)
        }
    }

    func testDuplicateDetectionMatchesAcrossSpellings() {
        let owned = Supplement(name: "Whey", kind: .protein)
        owned.upc = "748927028669"
        XCTAssertNotNil(Supplement.duplicate(forUPC: "0748927028669", name: "Other", in: [owned]))
        XCTAssertNil(Supplement.duplicate(forUPC: "031604026165", name: "Other", in: [owned]))
    }

    // MARK: - Wire shapes (captured from the real backend, Oct 2026)

    func testLookupDTODecodesIngredientsAndOldPayloadsWithout() throws {
        let withIngredients = """
        {"upc":"768990017926","brand":"Nordic Naturals","name":"Ultimate Omega-D3 Lemon","kind":"omega3",
         "dose_per_serving":"2 Softgel","servings_per_container":45,"certifications":[],"source":"dsld",
         "ingredients":["Vitamin D3 25 mcg","Total Omega-3 Fatty Acids 1280 mg"]}
        """
        let dto = try JSONDecoder().decode(SupplementLookupDTO.self, from: Data(withIngredients.utf8))
        XCTAssertEqual(dto.ingredients?.count, 2)
        let old = #"{"upc":"1","name":"x","kind":"other","certifications":[],"source":"dsld"}"#
        XCTAssertNil(try JSONDecoder().decode(SupplementLookupDTO.self, from: Data(old.utf8)).ingredients)
    }

    func testSearchHitDecodes() throws {
        let json = #"[{"id":"181813","brand":"Thorne","name":"Magnesium Bisglycinate","kind":"vitamin","net_contents":"90 Capsule(s)","on_market":true}]"#
        let hits = try JSONDecoder().decode([SupplementSearchHit].self, from: Data(json.utf8))
        XCTAssertEqual(hits.first?.id, "181813")
        XCTAssertEqual(hits.first?.netContents, "90 Capsule(s)")
        XCTAssertEqual(hits.first?.onMarket, true)
    }

    // MARK: - Label photo reader

    func testLabelReadingMapsToADTO() throws {
        let raw = """
        ```json
        {"name":"Ultimate Omega","brand":"Nordic Naturals","kind":"omega3","serving":"2 softgels",
         "servings_per_container":45,"per_serving":{"kcal":20,"protein":0,"carbs":null,"fat":2},
         "ingredients":["Vitamin D3 25 mcg","EPA 650 mg"]}
        ```
        """
        let dto = try SupplementLabelReader.parse(raw, upc: "768990017926")
        XCTAssertEqual(dto.name, "Ultimate Omega")
        XCTAssertEqual(dto.kind, "omega3")
        XCTAssertEqual(dto.dosePerServing, "2 softgels")
        XCTAssertEqual(dto.servingsPerContainer, 45)
        XCTAssertEqual(dto.caloriesPerServing, 20)
        XCTAssertNil(dto.proteinGramsPerServing, "zero means none")
        XCTAssertEqual(dto.fatGramsPerServing, 2)
        XCTAssertEqual(dto.source, "label")
        XCTAssertEqual(dto.upc, "768990017926")
        XCTAssertEqual(dto.ingredients, ["Vitamin D3 25 mcg", "EPA 650 mg"])
    }

    func testUnknownKindFallsBackAndNoNameIsUnreadable() throws {
        let dto = try SupplementLabelReader.parse(#"{"name":"Mystery","kind":"banana"}"#, upc: nil)
        XCTAssertEqual(dto.kind, "other")
        XCTAssertThrowsError(try SupplementLabelReader.parse(#"{"name":null}"#, upc: nil))
        XCTAssertThrowsError(try SupplementLabelReader.parse("no json here", upc: nil))
    }

    // MARK: - Prefill → shelf item

    func testLookupBecomesAShelfItemWithIngredients() {
        let dto = SupplementLookupDTO(
            upc: "768990017926", brand: "Nordic Naturals", name: "Ultimate Omega-D3 Lemon", kind: "omega3",
            dosePerServing: "2 Softgel", servingsPerContainer: 45, proteinGramsPerServing: nil,
            certifications: [], source: "dsld", ingredients: ["Vitamin D3 25 mcg"]
        )
        let supplement = Supplement(lookup: dto)
        XCTAssertEqual(supplement.ingredientsSummary, "Vitamin D3 25 mcg")
        XCTAssertEqual(supplement.servingsRemaining, 45)
        XCTAssertEqual(supplement.upc, "768990017926")
    }
}

// MARK: - Shelf board + history

@MainActor
final class SupplementShelfBoardTests: XCTestCase {
    private func dose(_ s: Supplement, minutes: Int, anchor: SupplementTimingAnchor?, take: Bool = true) -> SupplementDose {
        SupplementDose(
            supplementID: s.id, name: s.name, kind: s.kind, dosePerServing: s.dosePerServing,
            take: take, minutes: minutes, anchor: anchor, reason: "Daily"
        )
    }

    func testGroupsByTheSamePeriodsAsTodayAndSortsByClock() {
        let creatine = Supplement(name: "Creatine", kind: .creatine, dosePerServing: "5 g")
        let d3 = Supplement(name: "D3", kind: .vitamin)
        let magnesium = Supplement(name: "Magnesium", kind: .vitamin)
        let whey = Supplement(name: "Whey", kind: .protein)
        let doses = [
            dose(creatine, minutes: 8 * 60, anchor: .breakfast),
            dose(d3, minutes: 7 * 60 + 30, anchor: .wake),
            dose(magnesium, minutes: 23 * 60, anchor: .bedtime),
            dose(whey, minutes: 13 * 60, anchor: .lunch),
        ]

        let sections = SupplementShelfBoard.build(supplements: [creatine, d3, magnesium, whey], doses: doses, recentLogs: [])

        XCTAssertEqual(sections.map(\.period), [.morning, .withMeals, .evening])
        XCTAssertEqual(sections[0].rows.map(\.supplement.name), ["D3", "Creatine"])
        XCTAssertEqual(sections[2].rows.first?.supplement.name, "Magnesium")
        XCTAssertEqual(sections[0].rows.last?.scheduleLine, "08:00 · With breakfast")
    }

    func testRowShowsBrandDoseAndStock() {
        let s = Supplement(name: "Creatine", kind: .creatine, dosePerServing: "5 g", servingsRemaining: 40)
        s.brand = "Thorne"
        s.servingsPerContainer = 90
        let row = SupplementShelfBoard.build(
            supplements: [s], doses: [dose(s, minutes: 480, anchor: .breakfast)], recentLogs: []
        ).first?.rows.first
        XCTAssertEqual(row?.brandDoseLine, "Thorne · 5 g")
        XCTAssertEqual(row?.stockLine, "40 days left")
        XCTAssertEqual(row?.needsReorder, false)
    }

    func testLowStockRowFlagsReorder() {
        let s = Supplement(name: "Creatine", kind: .creatine, dosePerServing: "5 g", servingsRemaining: 3)
        s.servingsPerContainer = 90
        let row = SupplementShelfBoard.build(
            supplements: [s], doses: [dose(s, minutes: 480, anchor: .breakfast)], recentLogs: []
        ).first?.rows.first
        XCTAssertEqual(row?.needsReorder, true)
        XCTAssertEqual(row?.stockLine, "3 days left")
    }

    func testArchivedAndDoselessItemsAreLeftOut() {
        let archived = Supplement(name: "Old", kind: .other, isArchived: true)
        let noDose = Supplement(name: "NoDose", kind: .other)
        XCTAssertTrue(SupplementShelfBoard.build(supplements: [archived, noDose], doses: [dose(archived, minutes: 480, anchor: .wake)], recentLogs: []).isEmpty)
    }

    func testHistoryCountsDistinctDaysInTheWindow() {
        let s = Supplement(name: "Creatine", kind: .creatine)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func log(_ daysAgo: Int, id: UUID? = s.id) -> SupplementIntakeLog {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            return SupplementIntakeLog(supplementName: s.name, supplementID: id, day: day)
        }
        let logs = [log(0), log(1), log(1), log(5), log(40), log(2, id: UUID())]
        let history = SupplementHistory.summary(logs: logs, supplementID: s.id, supplementName: s.name)
        XCTAssertEqual(history.takenDays, 3)
        XCTAssertEqual(history.recent.count, 4)
        XCTAssertEqual(history.windowDays, 14)
    }
}
