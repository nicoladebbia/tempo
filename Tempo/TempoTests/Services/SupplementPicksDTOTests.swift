//
// SupplementPicksDTOTests.swift
// Tempo
//
// Wire-format tests for SupplementLookupDTO / SupplementPicksDTO
// (APIEndpoints+Supplements.swift): the backend encodes snake_case and this
// app's decoder has no key strategy, so every field relies on its explicit
// CodingKeys to match. These pin that contract without a live server.
//

import Foundation
@testable import Tempo
import XCTest

final class SupplementPicksDTOTests: XCTestCase {
    private func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    // MARK: - SupplementLookupDTO

    func testDecodesLookupDTOFromSnakeCaseJSON() throws {
        let json = """
        {
            "upc": "748927060140",
            "brand": "Optimum Nutrition",
            "name": "Gold Standard 100% Whey",
            "kind": "protein",
            "dose_per_serving": "30.4 g",
            "servings_per_container": 74,
            "protein_grams_per_serving": 24,
            "certifications": ["Informed Sport"],
            "source": "openfoodfacts"
        }
        """
        let dto = try makeDecoder().decode(SupplementLookupDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.upc, "748927060140")
        XCTAssertEqual(dto.brand, "Optimum Nutrition")
        XCTAssertEqual(dto.dosePerServing, "30.4 g")
        XCTAssertEqual(dto.servingsPerContainer, 74)
        XCTAssertEqual(dto.proteinGramsPerServing, 24)
        XCTAssertEqual(dto.certifications, ["Informed Sport"])
        XCTAssertEqual(dto.source, "openfoodfacts")
    }

    func testDecodesLookupDTOWithNullOptionalFields() throws {
        let json = """
        {
            "upc": "012345678905",
            "brand": null,
            "name": "Unknown Supplement",
            "kind": "other",
            "dose_per_serving": null,
            "servings_per_container": null,
            "protein_grams_per_serving": null,
            "certifications": [],
            "source": "openfoodfacts"
        }
        """
        let dto = try makeDecoder().decode(SupplementLookupDTO.self, from: Data(json.utf8))
        XCTAssertNil(dto.brand)
        XCTAssertNil(dto.dosePerServing)
        XCTAssertNil(dto.servingsPerContainer)
        XCTAssertTrue(dto.certifications.isEmpty)
    }

    // MARK: - SupplementPicksDTO

    func testDecodesVerifiedPicksDTOFromSnakeCaseJSON() throws {
        let json = """
        {
            "kind": "creatine",
            "verified": true,
            "look_for": "Creatine monohydrate, third-party tested.",
            "picks": [
                {
                    "brand": "Thorne",
                    "product": "Creatine Monohydrate",
                    "form": "powder",
                    "certifications": ["NSF Certified for Sport"],
                    "why": "Widely available, unflavored, third-party tested.",
                    "approx_price_per_serving_usd": 0.45,
                    "price_as_of": "2026-09",
                    "buy_links": [
                        {"label": "Brand", "url": "https://www.thorne.com/products/dp/creatine"},
                        {"label": "Amazon", "url": "https://www.amazon.com/s?k=Thorne+Creatine"}
                    ]
                }
            ]
        }
        """
        let dto = try makeDecoder().decode(SupplementPicksDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.kind, "creatine")
        XCTAssertTrue(dto.verified)
        XCTAssertEqual(dto.lookFor, "Creatine monohydrate, third-party tested.")
        XCTAssertEqual(dto.picks.count, 1)

        let pick = try XCTUnwrap(dto.picks.first)
        XCTAssertEqual(pick.brand, "Thorne")
        XCTAssertEqual(pick.certifications, ["NSF Certified for Sport"])
        XCTAssertEqual(pick.approxPricePerServingUSD, 0.45)
        XCTAssertEqual(pick.priceAsOf, "2026-09")
        XCTAssertEqual(pick.buyLinks.count, 2)
        XCTAssertEqual(pick.buyLinks.first?.label, "Brand")
        XCTAssertEqual(pick.id, "Thorne|Creatine Monohydrate")
    }

    func testDecodesUnverifiedAIFallbackPicksDTO() throws {
        let json = """
        {
            "kind": "other",
            "verified": false,
            "look_for": "Look for a reputable brand with third-party testing.",
            "picks": []
        }
        """
        let dto = try makeDecoder().decode(SupplementPicksDTO.self, from: Data(json.utf8))
        XCTAssertFalse(dto.verified)
        XCTAssertTrue(dto.picks.isEmpty)
    }
}
