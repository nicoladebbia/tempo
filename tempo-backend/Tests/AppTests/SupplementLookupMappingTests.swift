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

// MARK: - Real DSLD label fixtures (captured Oct 2026 from /dsld/v9/label/{id})

struct DSLDRealLabelMappingTests {
    /// ON Gold Standard — no protein row, "Total Carbohydrates" plural, empty notes elsewhere.
    private let wheyJSON = """
    {"id":289172,"brandName":"Optimum Nutrition","fullName":"Gold Standard 100% Whey Double Rich Chocolate",
     "upcSku":"7 48927 02866 9","offMarket":0,"entryDate":"2022-01-01","servingsPerContainer":74,
     "productType":{"langualCodeDescription":"Multi-Vitamin and Mineral (MVM)"},
     "netContents":[{"quantity":5,"unit":"lb(s)","display":"5 lb(s)"}],
     "servingSizes":[{"minQuantity":30.4,"unit":"Gram(s)","notes":"1 Scoop"}],
     "statements":[{"type":"Formula re: Contains","notes":"Packed with 24 grams of high-quality protein per serving to help build muscle."}],
     "ingredientRows":[
       {"name":"Calories","category":"other","quantity":[{"quantity":120,"unit":"Calorie(s)"}]},
       {"name":"Total Fat","category":"fat","quantity":[{"quantity":1.5,"unit":"Gram(s)"}]},
       {"name":"Total Carbohydrates","category":"sugar","quantity":[{"quantity":3,"unit":"Gram(s)"}]},
       {"name":"Calcium","category":"mineral","quantity":[{"quantity":130,"unit":"mg"}]}]}
    """

    /// Nordic Naturals — empty notes, servingsPerContainer null → derived from net contents.
    private let omegaJSON = """
    {"id":288763,"brandName":"Nordic Naturals","fullName":"Ultimate Omega-D3 Lemon","upcSku":"7 68990 01792 6",
     "offMarket":0,"servingsPerContainer":null,
     "productType":{"langualCodeDescription":"Fatty Acid"},
     "netContents":[{"quantity":90,"unit":"Softgel(s)","display":"90 Softgel(s)"}],
     "servingSizes":[{"minQuantity":2,"unit":"Softgel(s)","notes":""}],
     "ingredientRows":[
       {"name":"Calories","category":"other","quantity":[{"quantity":20,"unit":"Calorie(s)"}]},
       {"name":"Vitamin D3","category":"vitamin","quantity":[{"quantity":25,"unit":"mcg"}]},
       {"name":"Total Omega-3 Fatty Acids","category":"fatty acid","quantity":[{"quantity":1280,"unit":"mg"}]}]}
    """

    @Test func wheyIsProteinNotMultivitaminAndGetsMacrosFromStatements() throws {
        let label = try JSONDecoder().decode(DSLDLabel.self, from: Data(wheyJSON.utf8))
        let dto = SupplementLookupAPIClient.merge(upc: "748927028669", off: nil, dsld: label)
        #expect(dto.kind == "protein")
        #expect(dto.dosePerServing == "30.4 g (1 Scoop)")
        #expect(dto.servingsPerContainer == 74)
        #expect(dto.proteinGramsPerServing == 24)
        #expect(dto.caloriesPerServing == 120)
        #expect(dto.carbsGramsPerServing == 3)
        #expect(dto.fatGramsPerServing == 1.5)
        #expect(dto.source == "dsld")
    }

    @Test func omegaDerivesServingsAndListsActives() throws {
        let label = try JSONDecoder().decode(DSLDLabel.self, from: Data(omegaJSON.utf8))
        let dto = SupplementLookupAPIClient.merge(upc: "768990017926", off: nil, dsld: label)
        #expect(dto.kind == "omega3")
        #expect(dto.dosePerServing == "2 Softgel")
        #expect(dto.servingsPerContainer == 45)
        #expect(dto.ingredients == ["Vitamin D3 25 mcg", "Total Omega-3 Fatty Acids 1280 mg"])
    }

    @Test func offFillsWheyProteinWhenDSLDLacksIt() throws {
        let noProtein = wheyJSON.replacingOccurrences(of: "24 grams of high-quality protein", with: "great taste")
        let label = try JSONDecoder().decode(DSLDLabel.self, from: Data(noProtein.utf8))
        let off = try JSONDecoder().decode(
            OFFProduct.self,
            from: Data(#"{"product_name":"100% Whey","brands":"Optimum Nutrition","nutriments":{"proteins_serving":24}}"#.utf8)
        )
        let dto = SupplementLookupAPIClient.merge(upc: "748927028669", off: off, dsld: label)
        #expect(dto.proteinGramsPerServing == 24)
    }

    @Test func openProductsFactsSourceIsReported() throws {
        let off = try JSONDecoder().decode(OFFProduct.self, from: Data(#"{"product_name":"Magnesium 400","brands":"Thorne"}"#.utf8))
        let dto = SupplementLookupAPIClient.merge(upc: "693749000000", off: off, dsld: nil, offSource: "openproductsfacts")
        #expect(dto.source == "openproductsfacts")
        #expect(dto.kind == "vitamin")
    }

    @Test func searchHitsAreDedupedAndOnMarketFirst() throws {
        let json = """
        {"hits":[
         {"_id":"1","_source":{"brandName":"Thorne","fullName":"Magnesium Bisglycinate","offMarket":1}},
         {"_id":"2","_source":{"brandName":"Thorne","fullName":"Magnesium Bisglycinate","offMarket":1}},
         {"_id":"3","_source":{"brandName":"Thorne","fullName":"Magnesium Citramate","offMarket":0,"netContents":[{"quantity":90,"unit":"Capsule(s)","display":"90 Capsule(s)"}]}}]}
        """
        let resp = try JSONDecoder().decode(DSLDSearchResponse.self, from: Data(json.utf8))
        let hits = SupplementLookupAPIClient.mapSearchHits(resp)
        #expect(hits.map(\.id) == ["dsld:3", "dsld:1"])
        #expect(hits[0].netContents == "90 Capsule(s)")
        #expect(hits[0].kind == "vitamin")
    }

    @Test func bestLabelPrefersOnMarketThenNewest() throws {
        func label(_ off: Int, _ date: String) throws -> DSLDLabel {
            try JSONDecoder().decode(DSLDLabel.self, from: Data(#"{"offMarket":\#(off),"entryDate":"\#(date)"}"#.utf8))
        }
        let best = SupplementLookupAPIClient.pickBestLabel([
            ("a", try label(1, "2024-01-01")), ("b", try label(0, "2020-01-01")), ("c", try label(0, "2022-01-01")),
        ])
        #expect(best?.entryDate == "2022-01-01")
    }
}
