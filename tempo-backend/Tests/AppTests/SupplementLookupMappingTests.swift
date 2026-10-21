@testable import App
import Foundation
import Testing

// Response-mapping tests for SupplementLookupAPIClient — decode real-shaped
// fixture JSON (captured from live Open Food Facts / DSLD calls during
// research) into the wire DTOs, then exercise the internal `merge` directly.
// No network calls in these tests.

struct SupplementLookupMappingTests {
    private let offOnlyJSON = """
    {
      "status": 1,
      "product": {
        "product_name": "Gold Standard 100% Whey",
        "generic_name": "Whey protein powder",
        "brands": "Optimum Nutrition,ON",
        "categories": "Protein powders, Whey protein",
        "ingredients_text": "Whey Protein Isolate, Whey Protein Concentrate, Natural and Artificial Flavors. Informed Sport certified.",
        "serving_size": "30.4 g",
        "quantity": "2.27 kg",
        "labels_tags": ["en:informed-sport"],
        "nutriments": { "proteins_serving": 24 }
      }
    }
    """

    private let dsldLabelJSON = """
    {
      "brandName": "Optimum Nutrition",
      "fullName": "Gold Standard 100% Whey - Double Rich Chocolate",
      "productType": { "langualCodeDescription": "Protein Supplement" },
      "servingsPerContainer": 74,
      "servingSizes": [{ "minQuantity": 1, "unit": "Scoop(s)", "notes": "1 scoop (30.4 g)" }],
      "ingredientRows": [
        { "name": "Whey Protein Isolate", "category": "Protein", "quantity": [{ "quantity": 24000, "unit": "Milligram(s)" }] }
      ],
      "statements": [{ "type": "Certification", "notes": "NSF Certified for Sport" }]
    }
    """

    @Test func mapsOFFOnlyProductWhenDSLDEnrichmentIsUnavailable() throws {
        let off = try JSONDecoder().decode(OFFResponse.self, from: Data(offOnlyJSON.utf8))
        let product = try #require(off.product)

        let dto = SupplementLookupAPIClient.merge(upc: "748927060140", off: product, dsld: nil)

        #expect(dto.upc == "748927060140")
        #expect(dto.brand == "Optimum Nutrition")
        #expect(dto.name == "Gold Standard 100% Whey")
        #expect(dto.kind == "protein")
        #expect(dto.dosePerServing == "30.4 g")
        #expect(dto.proteinGramsPerServing == 24)
        #expect(dto.certifications == ["Informed Sport"])
        #expect(dto.source == "openfoodfacts")
    }

    @Test func mapsMergedOFFAndDSLDPreferringDSLDForDoseAndCertifications() throws {
        let off = try JSONDecoder().decode(OFFResponse.self, from: Data(offOnlyJSON.utf8))
        let product = try #require(off.product)
        let dsld = try JSONDecoder().decode(DSLDLabel.self, from: Data(dsldLabelJSON.utf8))

        let dto = SupplementLookupAPIClient.merge(upc: "748927060140", off: product, dsld: dsld)

        #expect(dto.name == "Gold Standard 100% Whey - Double Rich Chocolate")
        #expect(dto.dosePerServing == "1 scoop (30.4 g)")
        #expect(dto.servingsPerContainer == 74)
        #expect(dto.proteinGramsPerServing == 24)
        #expect(dto.certifications.contains("NSF Certified for Sport"))
        #expect(dto.certifications.contains("Informed Sport"))
        #expect(dto.source == "dsld")
    }

    @Test func mapsOFFMacrosPerServing() throws {
        let json = """
        {"status":1,"product":{"product_name":"Mass Gainer","serving_size":"150 g",
         "nutriments":{"proteins_serving":50,"energy-kcal_serving":620,"carbohydrates_serving":95,"fat_serving":6}}}
        """
        let off = try JSONDecoder().decode(OFFResponse.self, from: Data(json.utf8))
        let dto = SupplementLookupAPIClient.merge(upc: "1", off: try #require(off.product), dsld: nil)
        #expect(dto.caloriesPerServing == 620)
        #expect(dto.carbsGramsPerServing == 95)
        #expect(dto.fatGramsPerServing == 6)
    }

    @Test func mapsDSLDMacroRowsAndLeavesAbsentMacrosNil() throws {
        let dsldJSON = """
        {"brandName":"X","fullName":"Y","ingredientRows":[
          {"name":"Calories","quantity":[{"quantity":120,"unit":"Calorie(s)"}]},
          {"name":"Total Fat","quantity":[{"quantity":1500,"unit":"Milligram(s)"}]},
          {"name":"Total Carbohydrate","quantity":[{"quantity":3,"unit":"Gram(s)"}]}]}
        """
        let dsld = try JSONDecoder().decode(DSLDLabel.self, from: Data(dsldJSON.utf8))
        let off = try JSONDecoder().decode(OFFResponse.self, from: Data(offOnlyJSON.utf8))
        let dto = SupplementLookupAPIClient.merge(upc: "1", off: try #require(off.product), dsld: dsld)
        #expect(dto.caloriesPerServing == 120)
        #expect(dto.fatGramsPerServing == 1.5)
        #expect(dto.carbsGramsPerServing == 3)

        let plain = SupplementLookupAPIClient.merge(upc: "1", off: try #require(off.product), dsld: nil)
        #expect(plain.caloriesPerServing == nil)
        #expect(plain.fatGramsPerServing == nil)
    }

    @Test func offResponseWithZeroStatusHasNoProduct() throws {
        let json = """
        {"status": 0, "product": null}
        """
        let off = try JSONDecoder().decode(OFFResponse.self, from: Data(json.utf8))
        #expect(off.status == 0)
        #expect(off.product == nil)
    }

    @Test func derivesServingsFromQuantityAndServingSizeWhenDSLDMissing() throws {
        let off = try JSONDecoder().decode(OFFResponse.self, from: Data(offOnlyJSON.utf8))
        let product = try #require(off.product)
        // 2270 g / 30.4 g ≈ 74.7 → rounds to 75
        #expect(product.derivedServingsPerContainer == 75)
    }

    @Test func derivedServingsIsNilWhenItRoundsToZero() throws {
        let json = offOnlyJSON
            .replacingOccurrences(of: "\"quantity\": \"2.27 kg\"", with: "\"quantity\": \"5 mg\"")
        let off = try JSONDecoder().decode(OFFResponse.self, from: Data(json.utf8))
        #expect(try #require(off.product).derivedServingsPerContainer == nil)
    }
}

struct SupplementKindGuesserTests {
    @Test func guessesFromNameKeywords() {
        #expect(SupplementKindGuesser.guess(name: "Creatine Monohydrate", categories: nil, dsldProductType: nil) == .creatine)
        #expect(SupplementKindGuesser.guess(name: "Ultimate Omega Fish Oil", categories: nil, dsldProductType: nil) == .omega3)
        #expect(SupplementKindGuesser.guess(name: "Daily Multivitamin", categories: nil, dsldProductType: nil) == .multivitamin)
        #expect(SupplementKindGuesser.guess(name: "LMNT Electrolyte Mix", categories: nil, dsldProductType: nil) == .electrolytes)
        #expect(SupplementKindGuesser.guess(name: "C4 Pre-Workout", categories: nil, dsldProductType: nil) == .preworkout)
        #expect(SupplementKindGuesser.guess(name: "Gold Standard Whey", categories: nil, dsldProductType: nil) == .protein)
        #expect(SupplementKindGuesser.guess(name: "Vitamin D3 5000 IU", categories: nil, dsldProductType: nil) == .vitamin)
    }

    @Test func fallsBackToOtherWhenNothingMatches() {
        #expect(SupplementKindGuesser.guess(name: "Ashwagandha KSM-66", categories: nil, dsldProductType: nil) == .other)
    }

    @Test func usesCategoriesAndDSLDProductTypeAsSignal() {
        #expect(SupplementKindGuesser.guess(name: "Recovery Blend", categories: "Protein powders", dsldProductType: nil) == .protein)
        #expect(SupplementKindGuesser.guess(name: "Daily Support", categories: nil, dsldProductType: "Multivitamin/Mineral") == .multivitamin)
    }
}

struct SupplementCertificationScannerTests {
    @Test func findsKnownCertificationsCaseInsensitively() {
        #expect(SupplementCertificationScanner.scan("this product is nsf certified for sport") == ["NSF Certified for Sport"])
        #expect(SupplementCertificationScanner.scan("Informed Sport and USP Verified") == ["Informed Sport", "USP Verified"])
    }

    @Test func returnsEmptyForNilOrUnrelatedText() {
        #expect(SupplementCertificationScanner.scan(nil).isEmpty)
        #expect(SupplementCertificationScanner.scan("all natural, gluten free").isEmpty)
    }
}

struct SupplementGramsParsingTests {
    @Test func readsOnlyNumbersFollowedByAMassUnit() {
        #expect(OFFProduct.parseGrams("30.4 g") == 30.4)
        #expect(OFFProduct.parseGrams("2.27kg") == 2270)
        #expect(OFFProduct.parseGrams("2 x 30 g") == 30)
        #expect(OFFProduct.parseGrams("1,000 mg") == 1)
        #expect(OFFProduct.parseGrams("1,000 g") == 1000)
        #expect(OFFProduct.parseGrams("30,4 g") == 30.4)
        #expect(OFFProduct.parseGrams("0,500 kg") == 500)
        #expect(OFFProduct.parseGrams("1 capsule (500 mg)") == 0.5)
        #expect(OFFProduct.parseGrams("5 lbs")! > 2267 && OFFProduct.parseGrams("5 lbs")! < 2268)
    }

    @Test func countsAndScoopsAreNotGrams() {
        #expect(OFFProduct.parseGrams("2 gummies") == nil)
        #expect(OFFProduct.parseGrams("1 scoop") == nil)
        #expect(OFFProduct.parseGrams("60 tablets") == nil)
        #expect(OFFProduct.parseGrams(nil) == nil)
    }
}
