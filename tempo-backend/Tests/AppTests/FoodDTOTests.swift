import Testing
import Foundation
@testable import App

// USDA search → FoodDTO mapping: core macros required, fallback nutrient
// ids, sodium → salt, caps names tidied.
struct FoodDTOTests {

    private func food(_ nutrients: [(Int, Double)], name: String = "CHICKEN BREAST, RAW") -> USDASearchRawResponse.Food {
        USDASearchRawResponse.Food(
            fdcId: 42, description: name, dataType: "SR Legacy", brandOwner: nil, brandName: nil,
            gtinUpc: nil, servingSize: nil, servingSizeUnit: nil,
            foodNutrients: nutrients.map { USDASearchRawResponse.Nutrient(nutrientId: $0.0, value: $0.1) }
        )
    }

    @Test func mapsCoreMacrosAndSalt() throws {
        let dto = try #require(FoodDTO(usda: food([(1008, 120), (1003, 22.5), (1005, 0), (1004, 2.6), (1093, 400)])))
        #expect(dto.kcal == 120)
        #expect(dto.protein == 22.5)
        #expect(dto.salt == 1.0)
        #expect(dto.name == "Chicken Breast, Raw")
    }

    @Test func usesAtwaterEnergyWhenPlainEnergyMissing() throws {
        let dto = try #require(FoodDTO(usda: food([(2047, 110), (1003, 20), (1005, 1), (1004, 3)], name: "Chicken breast")))
        #expect(dto.kcal == 110)
        #expect(dto.name == "Chicken breast")
    }

    @Test func clampsNegativeFoundationValues() throws {
        let dto = try #require(FoodDTO(usda: food([(2047, 127), (1003, 21.4), (1005, -0.428), (1004, 4.78)])))
        #expect(dto.carbs == 0)
    }

    @Test func dropsFoodsWithoutCoreMacros() {
        #expect(FoodDTO(usda: food([(1258, 0.7)])) == nil)
    }

    @Test func decodesUSDAResponse() throws {
        let json = """
        {"foods":[{"fdcId":171515,"description":"Chicken tenders","dataType":"SR Legacy",
        "foodNutrients":[{"nutrientId":1008,"value":263},{"nutrientId":1003,"value":14.7},
        {"nutrientId":1005,"value":15},{"nutrientId":1004,"value":15.8},{"nutrientId":2000,"value":0.37}]}]}
        """
        let raw = try JSONDecoder().decode(USDASearchRawResponse.self, from: Data(json.utf8))
        let dto = try #require(raw.foods.compactMap(FoodDTO.init(usda:)).first)
        #expect(dto.fdcID == 171515)
        #expect(dto.sugars == 0.37)
    }
}
