//
// ReceiptItemResolverAccuracyTests.swift
// Tempo
//
// Permanent regression coverage for ReceiptItemResolver's dictionary+alias
// name resolution: every raw line from the 3 hand-verified Publix receipts
// used to build the round-2 receipt-parsing harness, plus ~80 synthetic
// lines across other chains (Walmart/GV, Target/GG, Costco/KS, Whole
// Foods/365, Trader Joe's/TJ, Kroger/ST, Aldi, and generic no-brand), each
// labeled with an expected core keyword the resolved name should contain.
// No fixture files or real photos involved — every case is a literal string
// below, so this runs standalone in CI. Asserts a floor on readable-name and
// canonical-food-name accuracy (currently both dictionaries hit 100%); if a
// future dictionary/alias change regresses coverage, this fails loudly
// instead of silently drifting.
//

import SwiftData
@testable import Tempo
import XCTest

@MainActor
final class ReceiptItemResolverAccuracyTests: XCTestCase {
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

    /// (raw, storeChain, expectedKeyword, expectedBrand). `expectedKeyword`
    /// nil = intentionally ungraded (genuinely ambiguous abbreviation, e.g.
    /// "T/T", or a non-food line) — still resolved (must not crash) but
    /// excluded from the accuracy denominator.
    private struct Case {
        let raw: String
        let chain: String?
        let expectedKeyword: String?
        let expectedBrand: String?
        init(_ raw: String, _ chain: String? = nil, _ expectedKeyword: String?, _ expectedBrand: String? = nil) {
            self.raw = raw
            self.chain = chain
            self.expectedKeyword = expectedKeyword
            self.expectedBrand = expectedBrand
        }
    }

    // MARK: - Real receipts (every line, r1 + r2 + r3)

    private let realReceiptCases: [Case] = [
        // r1.jpg (25 lines)
        Case("Extra S/F Peppermint", "publix", "peppermint"),
        Case("Oikos Triple Zro 4Pk Van", "publix", "oikos"),
        Case("Dave Kill Brd Bagel Every", "publix", "bagel"),
        Case("Wholly Avocado Smashed", "publix", "avocado"),
        Case("Pbx Classic Hummus", "publix", "hummus", "Publix"),
        Case("Iberia Coconut Water 1Lt", "publix", "coconut water"),
        Case("Aquafina Purified 24Pk", "publix", "aquafina"),
        Case("Quak Rice Cake Lt Salted", "publix", "rice cake"),
        Case("Topfox Pmk Seeds Chile Lm", "publix", "pumpkin seed"),
        Case("Quak Rice Cake Lt Salted", "publix", "rice cake"),
        Case("Egglands Lg Brwn Cge Free", "publix", "egg"),
        Case("Oatly Oatmilk", "publix", "oat milk"),
        Case("Gw Blue Tortilla Chips", "publix", "tortilla chip", "GreenWise"),
        Case("Iberia Coconut Water 1Lt", "publix", "coconut water"),
        Case("Carrots Microwave Publix", "publix", "carrot"),
        Case("Pbx A/B Boneless Breast", "publix", "breast", "Publix"),
        Case("Bulk Zucchini Squash", "publix", "zucchini"),
        Case("Hazelnuts", "publix", "hazelnut"),
        Case("Natural Almonds", "publix", "almond"),
        Case("Bagged Asparagus", "publix", "asparagus"),
        Case("Tropicana No Pulp", "publix", "tropicana"),
        Case("Tropicana No Pulp", "publix", "tropicana"),
        Case("Galbani Ricotta Protein", "publix", "ricotta"),
        Case("Kit Kat Bars", "publix", "kit kat"),
        Case("Bananas", "publix", "banana"),
        // r2.jpg (29 lines)
        Case("Zeph Sprng Wtr 24Pk (Pal)", "publix", "water"),
        Case("Oikos Triple Zro Bbry 4Pk", "publix", "oikos"),
        Case("Oikos Triple Zro 4Pk Van", "publix", "oikos"),
        Case("Simply Orange High Pulp", "publix", "simply orange"),
        Case("Simply Light Lemonade", "publix", "lemonade"),
        Case("Bananas", "publix", "banana"),
        Case("Oatly Oatmilk", "publix", "oat milk"),
        Case("President Unsltd Btr Bar", "publix", "butter"),
        Case("Simply Naked Organic Pita", "publix", "pita"),
        Case("Simply Naked Organic Pita", "publix", "pita"),
        Case("Peaches Premium", "publix", "peach"),
        Case("Iberia Jasmine Rice 5 Lb", "publix", "rice"),
        Case("Tates Choc Chip Ckie", "publix", "cookie"),
        Case("Tates Choc Chip Ckie", "publix", "cookie"),
        Case("Egglands Lg Brwn Cge Free", "publix", "egg"),
        Case("Petit Mango Nectar", "publix", "mango"),
        Case("Petit Mango Nectar", "publix", "mango"),
        Case("Petit Mango Nectar", "publix", "mango"),
        Case("Fruit Salad Medium", "publix", "fruit salad"),
        Case("Brownie Brittle Choc Chip", "publix", "brownie"),
        Case("Extra S/F Peppermint", "publix", "peppermint"),
        Case("Carrots Sticks Publix", "publix", "carrot"),
        Case("Natural Almonds", "publix", "almond"),
        Case("Walnuts", "publix", "walnut"),
        Case("Biscoff Cookies", "publix", "cookie"),
        Case("Yucatan Mild Guacamole", "publix", "guacamole"),
        Case("Watermelon Chunks Sdls Md", "publix", "watermelon"),
        Case("Watermelon Chunks Sdls Md", "publix", "watermelon"),
        Case("Pbx Classic Hummus", "publix", "hummus", "Publix"),
        // r3.jpg (34 lines; genuinely ambiguous/non-food ones ungraded)
        Case("Oik Trpl Zro Vanil", "publix", "oik"),
        Case("Oikos Tz 4Pk Blue", "publix", "oikos"),
        Case("Dkb Whl Grn Sd Brd", "publix", "bread"),
        Case("Dwny Sht Lav & Van", "publix", nil), // non-food (dryer sheets); ungraded
        Case("Bnls Chick Breast", "publix", "chicken"),
        Case("Ribeye Stk Bnls", "publix", "steak"),
        Case("Ribeye Stk Bnls", "publix", "steak"),
        Case("Zephyr Sprng Water", "publix", "water"),
        Case("Gw Eggs Xl Brown", "publix", "egg", "GreenWise"),
        Case("Zucchini Squash", "publix", "zucchini"),
        Case("Blueberries 11Oz", "publix", "blueberr"),
        Case("Celery Hlarts", "publix", "celery"),
        Case("Pbx Carrot Sticks", "publix", "carrot", "Publix"),
        Case("T/T Seasoned Crtn", "publix", nil), // ambiguous abbreviation; ungraded
        Case("Pbx Prosciutto Ps", "publix", "prosciutto", "Publix"),
        Case("Pbx Prosciutto Ps", "publix", "prosciutto", "Publix"),
        Case("Dawn Pwash Lemon", "publix", nil), // non-food (dish soap); ungraded
        Case("Dawn Dishspry Gain", "publix", nil), // non-food; ungraded
        Case("T/T Seasoned Crtn", "publix", nil),
        Case("Kell Rkt Original", "publix", "krispies"),
        Case("N V Granola Bars", "publix", "granola"),
        Case("N V Granola Bars", "publix", "granola"),
        Case("Y/C Catching Rays", "publix", nil), // ambiguous abbreviation; ungraded
        Case("Kinders Blck Grlic", "publix", "garlic"),
        Case("Oatly Oatmilk", "publix", "oat milk"),
        Case("Peppers Green Bell", "publix", "pepper"),
        Case("Cantaloupe Chunks", "publix", "cantaloupe"),
        Case("Wtrmln Chks Sdls", "publix", "watermelon"),
        Case("Pineapple Chks Sm", "publix", "pineapple"),
        Case("Peaches Premium", "publix", "peach"),
        Case("Crazy Pnut Butter", "publix", "peanut butter"),
        Case("Publix Classic Hum", "publix", "hummus", "Publix"),
        Case("Organic Bananas", "publix", "banana"),
    ]

    // MARK: - Synthetic lines across other chains (~80)

    private let syntheticCases: [Case] = [
        // Walmart (GV / Great Value) — 15
        Case("GV WHL MLK GAL", "walmart", "milk", "Great Value"),
        Case("GV 2PCT MLK GAL", "walmart", "milk", "Great Value"),
        Case("GV CHKN BRST BNLS", "walmart", "chicken", "Great Value"),
        Case("GV GRND BF 80/20", "walmart", "beef", "Great Value"),
        Case("GV STRWB JC", "walmart", "juice", "Great Value"),
        Case("GV FRZ VEG MIX", "walmart", "vegetable", "Great Value"),
        Case("GV WW BRD", "walmart", "bread", "Great Value"),
        Case("GV CHS SLCD", "walmart", "cheese", "Great Value"),
        Case("GV BTR UNSLTD", "walmart", "butter", "Great Value"),
        Case("GV NAT ALMND", "walmart", "almond", "Great Value"),
        Case("GV ORG BANANA", "walmart", "banana", "Great Value"),
        Case("GV BCN SLCD", "walmart", "bacon", "Great Value"),
        Case("GV YOG GRK", "walmart", "yogurt", "Great Value"),
        Case("GV TKY GRND", "walmart", "turkey", "Great Value"),
        Case("GV PNUT BTR", "walmart", "peanut butter", "Great Value"),
        // Target (GG / Good & Gather) — 10
        Case("GG ORG CHKN THGH", "target", "chicken", "Good & Gather"),
        Case("GG WHL WHT BRD", "target", "bread", "Good & Gather"),
        Case("GG GRK YOG PLN", "target", "yogurt", "Good & Gather"),
        Case("GG FRSH SALSA MED", "target", "salsa", "Good & Gather"),
        Case("GG SPKLNG WTR LM", "target", "water", "Good & Gather"),
        Case("GG FRZ STRWB", "target", "strawberry", "Good & Gather"),
        Case("GG NAT PNUT BTR", "target", "peanut butter", "Good & Gather"),
        Case("GG ORG BLUEB", "target", "blueberry", "Good & Gather"),
        Case("GG BF GRND 85/15", "target", "beef", "Good & Gather"),
        Case("GG CHS SHRD MOZZ", "target", "cheese", "Good & Gather"),
        // Costco (KS / Kirkland Signature) — 10
        Case("KS ORG EVOO 2LT", "costco", "olive oil", "Kirkland Signature"),
        Case("KS ALMND MLK", "costco", "almond milk", "Kirkland Signature"),
        Case("KS CHKN BRST BNLS SKNLS", "costco", "chicken", "Kirkland Signature"),
        Case("KS BCN THK CUT", "costco", "bacon", "Kirkland Signature"),
        Case("KS GRND CFE DK RST", "costco", "coffee", "Kirkland Signature"),
        Case("KS MXD NUTS", "costco", "nuts", "Kirkland Signature"),
        Case("KS TP 30RL", "costco", "toilet paper", "Kirkland Signature"),
        Case("KS WTR 40PK", "costco", "water", "Kirkland Signature"),
        Case("KS SHRD CHS MEX", "costco", "cheese", "Kirkland Signature"),
        Case("KS PRK TNDR", "costco", "pork", "Kirkland Signature"),
        // Whole Foods (365) — 10
        Case("365 ORG MLK WHL", "whole_foods", "milk", "365 by Whole Foods Market"),
        Case("365 GRK YOG PLN NFT", "whole_foods", "yogurt", "365 by Whole Foods Market"),
        Case("365 ORG CHKN BRTH", "whole_foods", "broth", "365 by Whole Foods Market"),
        Case("365 ALMND BTR", "whole_foods", "almond butter", "365 by Whole Foods Market"),
        Case("365 FRZ BERRIES MXD", "whole_foods", "berries", "365 by Whole Foods Market"),
        Case("365 ORG QUINOA", "whole_foods", "quinoa", "365 by Whole Foods Market"),
        Case("365 CHKN BRST ORG", "whole_foods", "chicken", "365 by Whole Foods Market"),
        Case("365 OLV OIL EVOO", "whole_foods", "olive oil", "365 by Whole Foods Market"),
        Case("365 GF OAT", "whole_foods", "oat", "365 by Whole Foods Market"),
        Case("365 ORG SALSA MED", "whole_foods", "salsa", "365 by Whole Foods Market"),
        // Trader Joe's (TJ) — 10
        Case("TJ EVERYTHING BGL SSNG", "trader_joes", "seasoning", "Trader Joe's"),
        Case("TJ ORG STRWB JAM", "trader_joes", "jam", "Trader Joe's"),
        Case("TJ CHKN TIKKA MSL", "trader_joes", "chicken", "Trader Joe's"),
        Case("TJ GRK YOG VAN", "trader_joes", "yogurt", "Trader Joe's"),
        Case("TJ CAULIFLOWER GNOCCHI", "trader_joes", "cauliflower", "Trader Joe's"),
        Case("TJ DRK CHOC PNUT BTR CUPS", "trader_joes", "chocolate", "Trader Joe's"),
        Case("TJ FRZ MANGO CHNKS", "trader_joes", "mango", "Trader Joe's"),
        Case("TJ ORG HUMMUS", "trader_joes", "hummus", "Trader Joe's"),
        Case("TJ ALMND FLR", "trader_joes", "almond flour", "Trader Joe's"),
        Case("TJ SPKLNG WTR GRPFRT", "trader_joes", "water", "Trader Joe's"),
        // Kroger (ST / Simple Truth) — 8
        Case("ST ORG MLK 2PCT", "kroger", "milk", "Simple Truth"),
        Case("ST GRK YOG STRWB", "kroger", "yogurt", "Simple Truth"),
        Case("ST CHKN BRST BNLS ORG", "kroger", "chicken", "Simple Truth"),
        Case("ST NAT PNUT BTR CRMY", "kroger", "peanut butter", "Simple Truth"),
        Case("ST FRZ BROC", "kroger", "broccoli", "Simple Truth"),
        Case("ST ALMND UNSLTD", "kroger", "almond", "Simple Truth"),
        Case("ST BF GRND LN 90/10", "kroger", "beef", "Simple Truth"),
        Case("ST WTR SPRNG", "kroger", "water", "Simple Truth"),
        // Aldi private label (no cataloged brand prefix yet — gap probe) — 5
        Case("SIMPLY NAT GRK YOG", "aldi", "yogurt"),
        Case("FIT ACTV PRO BAR", "aldi", "protein bar"),
        Case("L PNUT BTR CRMY", "aldi", "peanut butter"),
        Case("SEASON PIK STRWB", "aldi", "strawberry"),
        Case("FRIENDLY FRM MLK", "aldi", "milk"),
        // Generic, no store brand — 12
        Case("ORG BABY SPINACH", nil, "spinach"),
        Case("SWT POT MED", nil, "sweet potato"),
        Case("RED BELL PEPR", nil, "pepper"),
        Case("GRND TRKY 93/7", nil, "turkey"),
        Case("CHKN WNG FRZ", nil, "chicken wing"),
        Case("SALM FLT ATL", nil, "salmon"),
        Case("SHRMP RAW LG", nil, "shrimp"),
        Case("AVOCADO HASS", nil, "avocado"),
        Case("STRWB 1LB CLAM", nil, "strawberry"),
        Case("CUCMBR ENGLISH", nil, "cucumber"),
        Case("ONION YEL 3LB BG", nil, "onion"),
        Case("GRP TOM", nil, "tomato"),
    ]

    // MARK: - Measurement

    @discardableResult
    private func measure(_ label: String, cases: [Case], minAccuracyPercent: Double = 90) -> (readablePct: Double, canonicalPct: Double) {
        var readableHits = 0
        var canonicalHits = 0
        var graded = 0
        var readableMisses: [String] = []
        var canonicalMisses: [String] = []

        for c in cases {
            let result = ReceiptItemResolver.resolve(rawText: c.raw, storeChain: c.chain, in: context)
            guard let expected = c.expectedKeyword else {
                continue // ungraded row — still exercised, not scored
            }
            graded += 1
            let readableOK = result.readableName.lowercased().contains(expected.lowercased())
                && (c.expectedBrand == nil || result.matchedBrand?.lowercased().contains(c.expectedBrand!.lowercased()) == true)
            let canonicalOK = result.canonicalFoodName.lowercased().contains(expected.lowercased())
            if readableOK {
                readableHits += 1
            } else {
                readableMisses
                    .append(
                        "\(c.raw) -> readable='\(result.readableName)' brand=\(result.matchedBrand ?? "nil") (expected kw='\(expected)' brand=\(c.expectedBrand ?? "nil"))"
                    )
            }
            if canonicalOK {
                canonicalHits += 1
            } else {
                canonicalMisses.append("\(c.raw) -> canonical='\(result.canonicalFoodName)' (expected kw='\(expected)')")
            }
        }

        let readablePct = graded == 0 ? 0 : Double(readableHits) / Double(graded) * 100
        let canonicalPct = graded == 0 ? 0 : Double(canonicalHits) / Double(graded) * 100
        print(
            "[RESOLVERMEASURE] \(label): graded=\(graded) readableAccuracy=\(String(format: "%.1f", readablePct))% (\(readableHits)/\(graded)) canonicalAccuracy=\(String(format: "%.1f", canonicalPct))% (\(canonicalHits)/\(graded))"
        )
        for m in readableMisses {
            print("[READABLE-MISS \(label)] \(m)")
        }
        for m in canonicalMisses {
            print("[CANONICAL-MISS \(label)] \(m)")
        }

        XCTAssertGreaterThanOrEqual(
            readablePct, minAccuracyPercent,
            "\(label): readable-name accuracy dropped below \(Int(minAccuracyPercent))% — see [READABLE-MISS \(label)] lines above."
        )
        XCTAssertGreaterThanOrEqual(
            canonicalPct, minAccuracyPercent,
            "\(label): canonical-food accuracy dropped below \(Int(minAccuracyPercent))% — see [CANONICAL-MISS \(label)] lines above."
        )
        return (readablePct, canonicalPct)
    }

    func test_measure_realReceipts() {
        measure("real", cases: realReceiptCases)
    }

    func test_measure_synthetic() {
        measure("synthetic", cases: syntheticCases)
        XCTAssertGreaterThanOrEqual(syntheticCases.count, 78)
    }

    func test_measure_combined() {
        measure("combined", cases: realReceiptCases + syntheticCases)
    }
}
