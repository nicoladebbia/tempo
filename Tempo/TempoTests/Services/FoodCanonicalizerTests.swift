//
// FoodCanonicalizerTests.swift
// Tempo
//
// Coverage parity with NutriTrack food_matcher.py doctests, plus iOS-specific
// edge cases (Italian fixtures, receipt-style abbreviations, mixed casing).
//

@testable import Tempo
import XCTest

final class FoodCanonicalizerTests: XCTestCase {
    // MARK: - canonicalize

    func testCanonicalize_empty_returnsEmpty() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize(""), "")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("   "), "")
    }

    func testCanonicalize_directAliasHitsFirst() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("Grilled Chicken"), "chicken breast")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("Frozen Blueberries"), "berries")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("Latte d'avena"), "oat milk")
    }

    func testCanonicalize_parentheticalRemoval() {
        XCTAssertEqual(
            FoodCanonicalizer.canonicalize("Grilled Chicken Breast (200g)"),
            "chicken breast"
        )
        XCTAssertEqual(
            FoodCanonicalizer.canonicalize("rice (cooked)"),
            "rice"
        )
    }

    func testCanonicalize_stripsCookingPrefix() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("baked salmon"), "salmon")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("roasted sweet potato"), "sweet potato")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("frozen salmon"), "salmon")
    }

    func testCanonicalize_stripsCookingSuffix() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("rice cooked"), "rice")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("brown rice cooked"), "rice")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("oats raw"), "oats")
    }

    func testCanonicalize_italianFixtures() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("petto di pollo"), "chicken breast")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("pollo"), "chicken breast")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("gallette di riso"), "rice cakes")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("salmone"), "salmon")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("spinaci"), "spinach")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("mirtilli"), "berries")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("yogurt greco"), "greek yogurt")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("miele"), "honey")
    }

    func testCanonicalize_proteinPowderVariants() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("whey protein"), "protein powder")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("whey isolate"), "protein powder")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("casein"), "protein powder")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("proteine in polvere"), "protein powder")
    }

    func testCanonicalize_riceVariantsCollapse() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("white rice"), "rice")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("brown rice"), "rice")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("jasmine rice"), "rice")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("basmati rice"), "rice")
    }

    func testCanonicalize_pluralCollapse() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("bananas"), "banana")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("kiwis"), "kiwi")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("oranges"), "orange")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("avocados"), "avocado")
    }

    func testCanonicalize_receiptAbbreviation_bnls() {
        // Real receipt example — "BNLS BREAST" appears on Publix poultry lines.
        XCTAssertEqual(FoodCanonicalizer.canonicalize("bnls breast"), "chicken breast")
    }

    func testCanonicalize_oliveOilVariants() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("extra virgin olive oil"), "olive oil")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("evoo"), "olive oil")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("olio evo"), "olive oil")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("olio d'oliva"), "olive oil")
    }

    func testCanonicalize_bellPepperVariants() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("red bell pepper"), "bell pepper")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("green bell pepper"), "bell pepper")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("peperoni"), "bell pepper")
    }

    func testCanonicalize_caseAndWhitespaceTolerance() {
        XCTAssertEqual(FoodCanonicalizer.canonicalize("  CHICKEN  "), "chicken breast")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("Frozen   Blueberries"), "berries")
    }

    func testCanonicalize_unmappedReturnsCleaned() {
        // Something that isn't aliased should still get a sensible cleaned result.
        XCTAssertEqual(FoodCanonicalizer.canonicalize("Quinoa"), "quinoa")
        XCTAssertEqual(FoodCanonicalizer.canonicalize("baked quinoa"), "quinoa")
    }

    // MARK: - displayName

    func testDisplayName_stripsRedundantStateWords() {
        XCTAssertEqual(FoodCanonicalizer.displayName("cooked rice"), "Rice")
        XCTAssertEqual(FoodCanonicalizer.displayName("frozen blueberries"), "Blueberries")
        XCTAssertEqual(FoodCanonicalizer.displayName("brown rice cooked"), "Brown Rice")
    }

    func testDisplayName_keepsCookingMethods() {
        // "baked salmon" should display as "Baked Salmon" — cooking method preserved.
        XCTAssertEqual(FoodCanonicalizer.displayName("baked salmon"), "Baked Salmon")
        XCTAssertEqual(FoodCanonicalizer.displayName("grilled chicken"), "Grilled Chicken")
    }

    func testDisplayName_titleCases() {
        XCTAssertEqual(FoodCanonicalizer.displayName("chicken breast"), "Chicken Breast")
        XCTAssertEqual(FoodCanonicalizer.displayName("OLIVE OIL"), "Olive Oil")
    }

    func testDisplayName_empty() {
        XCTAssertEqual(FoodCanonicalizer.displayName(""), "")
    }

    // MARK: - foodMatches

    func testFoodMatches_canonicalEquivalence() {
        XCTAssertTrue(FoodCanonicalizer.foodMatches("frozen blueberries", "Berries"))
        XCTAssertTrue(FoodCanonicalizer.foodMatches("chicken breast", "Grilled Chicken Breast (200g)"))
        XCTAssertTrue(FoodCanonicalizer.foodMatches("petto di pollo", "chicken"))
    }

    func testFoodMatches_differentFoods() {
        XCTAssertFalse(FoodCanonicalizer.foodMatches("rice", "rice cakes"))
        XCTAssertFalse(FoodCanonicalizer.foodMatches("salmon", "chicken breast"))
    }

    func testFoodMatches_emptyInputs() {
        XCTAssertFalse(FoodCanonicalizer.foodMatches("", "rice"))
        XCTAssertFalse(FoodCanonicalizer.foodMatches("rice", ""))
        XCTAssertFalse(FoodCanonicalizer.foodMatches("", ""))
    }
}
