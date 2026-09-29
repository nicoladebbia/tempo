//
// ReceiptItemResolverTests.swift
// Tempo
//
// Covers the three resolution layers: dictionary expansion (real Publix
// ground-truth strings + synthetic lines across other chains), size/unit
// parsing, and the learned-alias round trip.
//

import SwiftData
@testable import Tempo
import XCTest

// MARK: - ReceiptItemResolverTests

@MainActor
final class ReceiptItemResolverTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: ReceiptItemAlias.self, configurations: config)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private var context: ModelContext {
        container.mainContext
    }

    private func resolve(_ rawText: String, chain: String? = nil) -> ReceiptResolvedItem {
        ReceiptItemResolver.resolve(rawText: rawText, storeChain: chain, in: context)
    }

    // MARK: - Real Publix ground-truth receipts

    func test_realPublixReceipts_dictionaryExpansion() {
        let cases: [(raw: String, chain: String?, expectedName: String, expectedBrand: String?)] = [
            ("PBX A/B Boneless Breast", "publix", "Publix Antibiotic-Free Boneless Breast", "Publix"),
            ("Egglands Lg Brwn Cge Free", nil, "Egglands Large Brown Cage Free", nil),
            ("Dave Kill Brd Bagel Every", nil, "Dave Killer Bread Bagel Everything", nil),
            ("Gw Blue Tortilla Chips", "publix", "GreenWise Blue Tortilla Chips", "GreenWise"),
            ("Dkb Whl Grn Sd Brd", nil, "Dave's Killer Bread Whole Grain Seed Bread", nil),
            ("Ribeye Stk Bnls", nil, "Ribeye Steak Boneless", nil),
        ]

        for testCase in cases {
            let result = resolve(testCase.raw, chain: testCase.chain)
            XCTAssertEqual(result.readableName, testCase.expectedName, "raw: \(testCase.raw)")
            XCTAssertEqual(result.matchedBrand, testCase.expectedBrand, "raw: \(testCase.raw)")
            XCTAssertEqual(result.confidence, .foodLevel, "raw: \(testCase.raw)")
            XCTAssertEqual(result.source, "dictionary", "raw: \(testCase.raw)")
            XCTAssertFalse(result.canonicalFoodName.isEmpty, "raw: \(testCase.raw)")
        }
    }

    /// GreenWise (Publix) vs Great Value (Walmart) — the "GW" prefix is
    /// context-dependent on storeChain, not resolvable from the dictionary
    /// alone.
    func test_gwPrefix_isContextDependentOnStoreChain() {
        let onPublix = resolve("Gw Blue Tortilla Chips", chain: "publix")
        XCTAssertEqual(onPublix.matchedBrand, "GreenWise")

        let onWalmart = resolve("Gw Blue Tortilla Chips", chain: "walmart")
        XCTAssertEqual(onWalmart.matchedBrand, "Great Value")
    }

    /// A line with no abbreviations and no store-brand prefix should not
    /// crash — it just falls back to a plain titlecase with unknown
    /// confidence.
    func test_lineWithNoDictionaryMatches_fallsBackCleanly() {
        let result = resolve("Bulk Zucchini Squash")
        XCTAssertEqual(result.readableName, "Bulk Zucchini Squash")
        XCTAssertEqual(result.confidence, .unknown)
        XCTAssertEqual(result.source, "fallback")
    }

    /// Non-food (household) line — must not crash, and should still expand
    /// via the dictionary since abbreviation expansion isn't food-specific.
    func test_nonFoodLine_doesNotCrash() {
        let result = resolve("Dwny Sht Lav & Van")
        XCTAssertEqual(result.readableName, "Downy Sheets Lavender & Vanilla")
        XCTAssertEqual(result.source, "dictionary")
    }

    // MARK: - Synthetic lines across other chains

    func test_syntheticLines_acrossChains() {
        let cases: [(raw: String, chain: String, expectedName: String, expectedBrand: String)] = [
            // Walmart (GV)
            ("GV Chkn Brst Bnls", "walmart", "Great Value Chicken Breast Boneless", "Great Value"),
            ("GV Shrd Chs Mex Blend", "walmart", "Great Value Shredded Cheese Mex Blend", "Great Value"),
            ("GV Frz Blueb 16OZ", "walmart", "Great Value Frozen Blueberry 16oz", "Great Value"),
            // Costco (KS) — including a leading item number, which must not
            // block brand-prefix detection.
            ("1234567 KS Almnd 3LB", "costco", "Kirkland Signature Almond 3lb", "Kirkland Signature"),
            ("KS Org Chkn Brst", "costco", "Kirkland Signature Organic Chicken Breast", "Kirkland Signature"),
            ("5566778 KS Prk Tndr", "costco", "Kirkland Signature Pork Tenderloin", "Kirkland Signature"),
            // Target (GG / spelled-out "Good & Gather")
            ("GG Org Whl Mlk", "target", "Good & Gather Organic Whole Milk", "Good & Gather"),
            ("Good & Gather Frz Strwb", "target", "Good & Gather Frozen Strawberry", "Good & Gather"),
            ("GG Bnls Sknls Chkn Thgh", "target", "Good & Gather Boneless Skinless Chicken Thigh", "Good & Gather"),
            // Trader Joe's (TJ / one-word "Traderjoes")
            ("TJ Org Avocado", "trader_joes", "Trader Joe's Organic Avocado", "Trader Joe's"),
            ("TJ Frz Rasp", "trader_joes", "Trader Joe's Frozen Raspberry", "Trader Joe's"),
            ("Traderjoes Almnd Btr", "trader_joes", "Trader Joe's Almond Butter", "Trader Joe's"),
            // Whole Foods (365 / WFM) — "365" is purely numeric, must still
            // be detected as a brand prefix, not dropped as noise.
            ("365 Org Chkn Brst", "whole_foods", "365 by Whole Foods Market Organic Chicken Breast", "365 by Whole Foods Market"),
            ("Wfm Grtd Parmesan", "whole_foods", "365 by Whole Foods Market Grated Parmesan", "365 by Whole Foods Market"),
            ("365 Frz Blueb 12OZ", "whole_foods", "365 by Whole Foods Market Frozen Blueberry 12oz", "365 by Whole Foods Market"),
        ]

        XCTAssertGreaterThanOrEqual(cases.count, 15)

        for testCase in cases {
            let result = resolve(testCase.raw, chain: testCase.chain)
            XCTAssertEqual(result.readableName, testCase.expectedName, "raw: \(testCase.raw)")
            XCTAssertEqual(result.matchedBrand, testCase.expectedBrand, "raw: \(testCase.raw)")
        }
    }

    // MARK: - Size / unit / pack-count parsing

    func test_sizeParsing_ozAndGallon() {
        let oz = resolve("Milk 16OZ")
        XCTAssertEqual(oz.sizeValue, 16)
        XCTAssertEqual(oz.sizeUnit, "oz")
        XCTAssertNil(oz.packCount)

        let ozSpaced = resolve("Milk 16 OZ")
        XCTAssertEqual(ozSpaced.sizeValue, 16)
        XCTAssertEqual(ozSpaced.sizeUnit, "oz")

        let gal = resolve("Water 1 GAL")
        XCTAssertEqual(gal.sizeValue, 1)
        XCTAssertEqual(gal.sizeUnit, "gal")
    }

    func test_sizeParsing_liters() {
        for raw in ["Soda 1LT", "Soda 1 LT", "Soda 1L", "Soda 1 L"] {
            let result = resolve(raw)
            XCTAssertEqual(result.sizeValue, 1, "raw: \(raw)")
            XCTAssertEqual(result.sizeUnit, "l", "raw: \(raw)")
        }
    }

    func test_sizeParsing_packAndCount() {
        let pack = resolve("Soda 6PK")
        XCTAssertEqual(pack.packCount, 6)

        let packSpaced = resolve("Soda 6 PK")
        XCTAssertEqual(packSpaced.packCount, 6)

        let count = resolve("Eggs 12CT")
        XCTAssertEqual(count.packCount, 12)

        let countSpaced = resolve("Eggs 12 CT")
        XCTAssertEqual(countSpaced.packCount, 12)
    }

    /// A 2-decimal weight like "1.32LB" on a meat line is a per-pound price
    /// weight, not a package size — sizeValue/sizeUnit must stay nil so the
    /// pipeline doesn't double-count it as a package size elsewhere.
    func test_sizeParsing_weightStyleValueIsNotTreatedAsPackageSize() {
        let result = resolve("Chkn Brst 1.32LB")
        XCTAssertNil(result.sizeValue)
        XCTAssertNil(result.sizeUnit)
        XCTAssertNil(result.packCount)
    }

    // MARK: - Learned alias round trip

    func test_learnedAlias_roundTrip() {
        let rawText = "Wcky Unrecognized Item 9Z"

        // Unknown text falls back before any correction is learned.
        let beforeLearn = resolve(rawText, chain: "publix")
        XCTAssertEqual(beforeLearn.confidence, .unknown)
        XCTAssertEqual(beforeLearn.source, "fallback")

        ReceiptItemResolver.learn(
            rawText: rawText,
            storeChain: "publix",
            readableName: "Publix Whacky Corrected Item",
            canonicalFoodName: "corrected item",
            in: context
        )

        let afterLearn = resolve(rawText, chain: "publix")
        XCTAssertEqual(afterLearn.confidence, .exactProduct)
        XCTAssertEqual(afterLearn.source, "learned_alias")
        XCTAssertEqual(afterLearn.readableName, "Publix Whacky Corrected Item")
        XCTAssertEqual(afterLearn.canonicalFoodName, "corrected item")

        // Confirming the same correction again bumps confirmCount instead
        // of creating a duplicate row.
        let firstAlias = ReceiptItemResolver.learn(
            rawText: rawText,
            storeChain: "publix",
            readableName: "Publix Whacky Corrected Item",
            canonicalFoodName: "corrected item",
            in: context
        )
        XCTAssertEqual(
            firstAlias.confirmCount,
            2,
            "starts at 1 on the initial learn(); this is the 2nd explicit learn() for the same key, so it should bump to 2"
        )

        let descriptor = FetchDescriptor<ReceiptItemAlias>()
        let allAliases = (try? context.fetch(descriptor)) ?? []
        XCTAssertEqual(allAliases.count, 1, "a repeat correction must update the existing row, not insert a duplicate")
    }

    // MARK: - Normalization

    func test_normalization_matchesDespiteWhitespaceAndCaseDifferences() {
        ReceiptItemResolver.learn(
            rawText: "  DKB   whl grn sd brd  ",
            storeChain: "publix",
            readableName: "Dave's Killer Bread — Whole Grain",
            canonicalFoodName: "bread",
            in: context
        )

        let result = resolve("dkb WHL GRN SD BRD", chain: "publix")
        XCTAssertEqual(result.confidence, .exactProduct)
        XCTAssertEqual(result.source, "learned_alias")
        XCTAssertEqual(result.readableName, "Dave's Killer Bread — Whole Grain")
    }

    func test_normalize_isPunctuationAndCaseInsensitive() {
        let a = ReceiptItemResolver.normalize("Publix Greek Yogurt, 0%!")
        let b = ReceiptItemResolver.normalize("  PUBLIX   greek yogurt 0  ")
        XCTAssertEqual(a, b)
    }
}
