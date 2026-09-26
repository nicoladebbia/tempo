import Vapor

// MARK: - Food Controller

// Generic-food search for the iOS food search screen, backed by USDA
// FoodData Central. Proxied (not called from the phone) so the USDA key
// stays server-side: USDA_API_KEY env var, falling back to the shared,
// heavily rate-limited DEMO_KEY.
//
// GET /v1/foods/search?q=chicken%20breast&limit=15
// Free for every signed-in user (not Pro-gated): searching is core logging.

struct FoodController: RouteCollection {
    let usdaClient: USDAFoodClient

    init(usdaClient: USDAFoodClient = USDAAPIClient()) {
        self.usdaClient = usdaClient
    }

    func boot(routes: RoutesBuilder) throws {
        routes.get("search", use: search)
    }

    @Sendable
    func search(req: Request) async throws -> Envelope<FoodSearchResponseDTO> {
        let query = (try? req.query.get(String.self, at: "q"))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard query.count >= 2, query.count <= 100 else {
            throw Abort(.badRequest, reason: "Query must be 2–100 characters.")
        }
        let limit = min(max((try? req.query.get(Int.self, at: "limit")) ?? 15, 1), 25)

        let raw: USDASearchRawResponse
        do {
            // Generic foods only — packaged products come from Open Food Facts on the phone.
            raw = try await usdaClient.search(query: query, dataTypes: ["Foundation", "SR Legacy"], pageSize: limit, on: req)
        } catch USDAClientError.tooManyRequests {
            throw Abort(.tooManyRequests, reason: "Food database is busy. Try again in a minute.")
        } catch USDAClientError.upstreamError {
            throw Abort(.badGateway, reason: "Food database unavailable.")
        }
        // Any other error (network failure, response decoding) propagates as-is,
        // matching the pre-refactor behavior where only the status-code switch
        // was special-cased and everything else bubbled up unmodified.
        let foods = raw.foods.compactMap(FoodDTO.init(usda:))
        return Envelope(data: FoodSearchResponseDTO(foods: foods))
    }
}

// MARK: - DTOs

struct FoodSearchResponseDTO: Content {
    let foods: [FoodDTO]
}

/// Nutrients per 100 g (USDA search reports Foundation, SR Legacy and
/// Branded values per 100 g).
struct FoodDTO: Content, Equatable {
    let fdcID: Int
    let name: String
    let brand: String?
    let barcode: String?
    let dataType: String
    let servingSize: Double?
    let servingUnit: String?
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let sugars: Double?
    let saturatedFat: Double?
    let fiber: Double?
    let salt: Double?

    enum CodingKeys: String, CodingKey {
        case fdcID = "fdc_id"
        case name, brand, barcode
        case dataType = "data_type"
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case kcal, protein, carbs, fat, sugars
        case saturatedFat = "saturated_fat"
        case fiber, salt
    }

    /// nil when the food lacks energy or any core macro.
    init?(usda food: USDASearchRawResponse.Food) {
        func value(_ ids: [Int]) -> Double? {
            for id in ids {
                if let nutrient = food.foodNutrients?.first(where: { $0.nutrientId == id }), let value = nutrient.value {
                    // Foundation foods can report tiny negatives (carbs by difference).
                    return max(0, value)
                }
            }
            return nil
        }
        guard let kcal = value([1008, 2047, 2048]),
              let protein = value([1003]),
              let carbs = value([1005, 1050]),
              let fat = value([1004, 1085])
        else {
            return nil
        }
        fdcID = food.fdcId
        name = Self.tidy(food.description)
        let brand = food.brandName ?? food.brandOwner
        self.brand = brand.map(Self.tidy)
        barcode = food.gtinUpc
        dataType = food.dataType ?? "Unknown"
        servingSize = food.servingSize
        servingUnit = food.servingSizeUnit
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        sugars = value([2000, 1063])
        saturatedFat = value([1258])
        fiber = value([1079])
        // Sodium mg → salt g.
        salt = value([1093]).map { $0 * 2.5 / 1000 }
    }

    /// USDA writes many names in caps ("CHICKEN BREAST"): title-case those.
    static func tidy(_ text: String) -> String {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, letters == letters.uppercased() else {
            return text
        }
        return text.capitalized
    }
}
