@testable import App
import Foundation
import Testing

// Wire-shape lock: SupplementLookupDTO / SupplementPicksDTO must serialize
// to exactly the snake_case keys the iOS client (feat/supplements-base)
// expects, regardless of the global .convertToSnakeCase strategy — these
// DTOs use explicit CodingKeys.

struct SupplementDTOTests {
    @Test func lookupDTOEncodesExpectedSnakeCaseKeys() throws {
        let dto = SupplementLookupDTO(
            upc: "748927060140",
            brand: "Optimum Nutrition",
            name: "Gold Standard 100% Whey",
            kind: "protein",
            dosePerServing: "1 scoop (30.4g)",
            servingsPerContainer: 74,
            proteinGramsPerServing: 24,
            certifications: ["Informed Sport"],
            source: "openfoodfacts"
        )
        let data = try JSONEncoder().encode(dto)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["dose_per_serving"] as? String == "1 scoop (30.4g)")
        #expect(object["servings_per_container"] as? Double == 74)
        #expect(object["protein_grams_per_serving"] as? Double == 24)
        #expect(object["upc"] as? String == "748927060140")
        #expect(object["brand"] as? String == "Optimum Nutrition")
        #expect(object["kind"] as? String == "protein")
        #expect(object["source"] as? String == "openfoodfacts")
        #expect((object["certifications"] as? [String]) == ["Informed Sport"])
    }

    @Test func lookupDTODecodesFromSnakeCaseJSON() throws {
        let json = """
        {"upc":"012345678905","brand":"Thorne","name":"Creatine Monohydrate","kind":"creatine",
         "dose_per_serving":"5 g","servings_per_container":90,"protein_grams_per_serving":null,
         "certifications":["NSF Certified for Sport"],"source":"dsld"}
        """
        let dto = try JSONDecoder().decode(SupplementLookupDTO.self, from: Data(json.utf8))
        #expect(dto.dosePerServing == "5 g")
        #expect(dto.servingsPerContainer == 90)
        #expect(dto.proteinGramsPerServing == nil)
        #expect(dto.certifications == ["NSF Certified for Sport"])
        #expect(dto.source == "dsld")
    }

    @Test func picksDTOEncodesExpectedSnakeCaseKeys() throws {
        let pick = SupplementPicksDTO.Pick(
            brand: "Thorne",
            product: "Creatine Monohydrate",
            form: "powder",
            certifications: ["NSF Certified for Sport"],
            why: "Third-party tested, unflavored, widely available.",
            approxPricePerServingUSD: 0.45,
            priceAsOf: "2026-09",
            buyLinks: [SupplementPicksDTO.BuyLink(label: "Brand", url: "https://www.thorne.com/products/dp/creatine")]
        )
        let dto = SupplementPicksDTO(kind: "creatine", picks: [pick], verified: true, lookFor: "Look for NSF Certified for Sport.")

        let data = try JSONEncoder().encode(dto)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["look_for"] as? String == "Look for NSF Certified for Sport.")
        #expect(object["verified"] as? Bool == true)

        let picks = try #require(object["picks"] as? [[String: Any]])
        let firstPick = try #require(picks.first)
        #expect(firstPick["approx_price_per_serving_usd"] as? Double == 0.45)
        #expect(firstPick["price_as_of"] as? String == "2026-09")
        let buyLinks = try #require(firstPick["buy_links"] as? [[String: Any]])
        #expect(buyLinks.first?["url"] as? String == "https://www.thorne.com/products/dp/creatine")
    }

    @Test func picksDTODecodesFromSnakeCaseJSON() throws {
        let json = """
        {"kind":"omega3","verified":false,"look_for":"Look for IFOS or NSF certification.",
         "picks":[{"brand":"Nordic Naturals","product":"Ultimate Omega","form":"softgel",
         "certifications":[],"why":"Popular option.","approx_price_per_serving_usd":0.6,
         "price_as_of":"2026-09","buy_links":[{"label":"Amazon","url":"https://www.amazon.com/s?k=Nordic+Naturals+Ultimate+Omega"}]}]}
        """
        let dto = try JSONDecoder().decode(SupplementPicksDTO.self, from: Data(json.utf8))
        #expect(dto.verified == false)
        #expect(dto.lookFor == "Look for IFOS or NSF certification.")
        let pick = try #require(dto.picks.first)
        #expect(pick.approxPricePerServingUSD == 0.6)
        #expect(pick.priceAsOf == "2026-09")
        #expect(pick.buyLinks.first?.label == "Amazon")
    }
}
