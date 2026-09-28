@testable import App
import Testing

// Slug-mapping: (kind, name) → curated catalog slug, or nil (AI fallback).

struct SupplementCatalogSlugTests {
    @Test func creatineAlwaysMatchesMonohydrate() {
        #expect(SupplementCatalogSlug.match(kind: "creatine", name: "Creatine") == .creatineMonohydrate)
        #expect(SupplementCatalogSlug.match(kind: "creatine", name: "") == .creatineMonohydrate)
    }

    @Test func fixedKindsMatchDirectly() {
        #expect(SupplementCatalogSlug.match(kind: "omega3", name: "Fish Oil") == .omega3FishOil)
        #expect(SupplementCatalogSlug.match(kind: "multivitamin", name: "Daily Multi") == .multivitamin)
        #expect(SupplementCatalogSlug.match(kind: "electrolytes", name: "LMNT") == .electrolytes)
        #expect(SupplementCatalogSlug.match(kind: "preworkout", name: "C4") == .preworkout)
    }

    @Test func proteinDisambiguatesByName() {
        #expect(SupplementCatalogSlug.match(kind: "protein", name: "Whey Isolate") == .wheyProtein)
        #expect(SupplementCatalogSlug.match(kind: "protein", name: "") == .wheyProtein)
        #expect(SupplementCatalogSlug.match(kind: "protein", name: "Casein Blend") == .caseinProtein)
        #expect(SupplementCatalogSlug.match(kind: "protein", name: "Vegan Pea Protein") == .plantProtein)
        #expect(SupplementCatalogSlug.match(kind: "protein", name: "Plant-Based Protein") == .plantProtein)
    }

    @Test func unusualProteinFallsBackToAI() {
        // Egg protein isn't in the curated catalog — must fall back, never
        // silently mismatch to whey.
        #expect(SupplementCatalogSlug.match(kind: "protein", name: "Egg White Protein") == nil)
    }

    @Test func vitaminDisambiguatesByName() {
        #expect(SupplementCatalogSlug.match(kind: "vitamin", name: "Vitamin D3 + K2") == .vitaminD3)
        #expect(SupplementCatalogSlug.match(kind: "vitamin", name: "Magnesium Glycinate") == .magnesium)
        #expect(SupplementCatalogSlug.match(kind: "vitamin", name: "Zinc Picolinate") == .zinc)
        #expect(SupplementCatalogSlug.match(kind: "vitamin", name: "Vitamin C 1000mg") == .vitaminC)
        #expect(SupplementCatalogSlug.match(kind: "vitamin", name: "B12 Methylcobalamin") == .b12)
        #expect(SupplementCatalogSlug.match(kind: "vitamin", name: "Iron Bisglycinate") == .iron)
    }

    @Test func unusualVitaminFallsBackToAI() {
        // e.g. Vitamin E isn't curated.
        #expect(SupplementCatalogSlug.match(kind: "vitamin", name: "Vitamin E") == nil)
    }

    @Test func otherDisambiguatesByName() {
        #expect(SupplementCatalogSlug.match(kind: "other", name: "Caffeine Pills") == .caffeine)
        #expect(SupplementCatalogSlug.match(kind: "other", name: "Melatonin 5mg") == .melatonin)
        #expect(SupplementCatalogSlug.match(kind: "other", name: "Collagen Peptides") == .collagen)
        #expect(SupplementCatalogSlug.match(kind: "other", name: "Ashwagandha KSM-66") == .ashwagandha)
        #expect(SupplementCatalogSlug.match(kind: "other", name: "Beta-Alanine") == .betaAlanine)
        #expect(SupplementCatalogSlug.match(kind: "other", name: "Beta Alanine") == .betaAlanine)
        #expect(SupplementCatalogSlug.match(kind: "other", name: "L-Citrulline") == .citrulline)
        #expect(SupplementCatalogSlug.match(kind: "other", name: "Probiotic 50B CFU") == .probiotic)
    }

    @Test func unusualOtherFallsBackToAI() {
        #expect(SupplementCatalogSlug.match(kind: "other", name: "Turmeric Curcumin") == nil)
    }

    @Test func unknownKindNeverMatches() {
        #expect(SupplementCatalogSlug.match(kind: "bogus", name: "Whey") == nil)
    }
}
