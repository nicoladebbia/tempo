//
// APIEndpoints+Supplements.swift
// Tempo
//
// Wire contract for the supplement catalog backend (feat/supplements):
//
//   GET /v1/supplements/lookup/:upc        → Envelope<SupplementLookupDTO>
//       Barcode → product (NIH DSLD first, Open Food Facts fallback).
//       404 when neither knows the code.
//   GET /v1/supplements/picks/:kind?name=… → Envelope<SupplementPicksDTO>
//       2–3 vetted, third-party-tested products for a supplement type.
//       `verified == false` means the AI fallback produced them (unusual
//       supplement not in the curated list) — the UI must say so.
//
// The backend encodes snake_case; this app's decoder has no key strategy,
// so CodingKeys spell every snake_case key.
//

import Foundation

// MARK: - SupplementLookupDTO

struct SupplementLookupDTO: Codable, Sendable, Equatable {
    let upc: String
    let brand: String?
    let name: String
    /// `SupplementKind.rawValue` best guess.
    let kind: String
    let dosePerServing: String?
    let servingsPerContainer: Double?
    let proteinGramsPerServing: Double?
    /// Optional macros per serving — absent from older backends / labels
    /// without them (decoded as nil).
    let caloriesPerServing: Double?
    let carbsGramsPerServing: Double?
    let fatGramsPerServing: Double?
    /// e.g. ["NSF Certified for Sport"] when the label/database says so.
    let certifications: [String]
    /// "dsld" | "openfoodfacts"
    let source: String

    init(
        upc: String, brand: String?, name: String, kind: String,
        dosePerServing: String?, servingsPerContainer: Double?,
        proteinGramsPerServing: Double?,
        caloriesPerServing: Double? = nil, carbsGramsPerServing: Double? = nil, fatGramsPerServing: Double? = nil,
        certifications: [String], source: String
    ) {
        self.upc = upc
        self.brand = brand
        self.name = name
        self.kind = kind
        self.dosePerServing = dosePerServing
        self.servingsPerContainer = servingsPerContainer
        self.proteinGramsPerServing = proteinGramsPerServing
        self.caloriesPerServing = caloriesPerServing
        self.carbsGramsPerServing = carbsGramsPerServing
        self.fatGramsPerServing = fatGramsPerServing
        self.certifications = certifications
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case upc
        case brand
        case name
        case kind
        case dosePerServing = "dose_per_serving"
        case servingsPerContainer = "servings_per_container"
        case proteinGramsPerServing = "protein_grams_per_serving"
        case caloriesPerServing = "calories_per_serving"
        case carbsGramsPerServing = "carbs_grams_per_serving"
        case fatGramsPerServing = "fat_grams_per_serving"
        case certifications
        case source
    }
}

// MARK: - SupplementPicksDTO

struct SupplementPicksDTO: Codable, Sendable, Equatable {
    let kind: String
    let picks: [Pick]
    /// true = curated, researched list; false = AI fallback (unverified).
    let verified: Bool
    /// What to look for in this type ("monohydrate; 3–5 g/day"), shown above the picks.
    let lookFor: String?

    struct Pick: Codable, Sendable, Equatable, Identifiable {
        let brand: String
        let product: String
        let form: String?
        let certifications: [String]
        let why: String
        let approxPricePerServingUSD: Double?
        /// "2026-09" — when the price was checked.
        let priceAsOf: String?
        let buyLinks: [BuyLink]

        var id: String { brand + "|" + product }

        enum CodingKeys: String, CodingKey {
            case brand
            case product
            case form
            case certifications
            case why
            case approxPricePerServingUSD = "approx_price_per_serving_usd"
            case priceAsOf = "price_as_of"
            case buyLinks = "buy_links"
        }
    }

    struct BuyLink: Codable, Sendable, Equatable {
        let label: String
        let url: String
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case picks
        case verified
        case lookFor = "look_for"
    }
}

// MARK: - Endpoints

extension APIEndpoint where Response == SupplementLookupDTO {
    static func supplementLookup(upc: String) -> Self {
        let digits = upc.filter(\.isNumber)
        return APIEndpoint(path: "/v1/supplements/lookup/\(digits)", method: .get)
    }
}

extension APIEndpoint where Response == SupplementPicksDTO {
    /// Pass `name` as the `name` query item (APIClient `queryItems:`).
    static func supplementPicks(kind: SupplementKind) -> Self {
        APIEndpoint(path: "/v1/supplements/picks/\(kind.rawValue)", method: .get)
    }
}
