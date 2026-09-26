import Vapor

// MARK: - USDAFoodClient

//
// Shared HTTP boundary for USDA FoodData Central. Two callers use this:
//   - FoodController (GET /v1/foods/search — the iOS food search screen)
//   - FoodNutritionResolver (resolves an AI-picked food description to
//     per-100g macros for the weekly meal plan macro engine)
//
// Both share the same key handling (USDA_API_KEY env var, falling back to
// the shared, heavily rate-limited DEMO_KEY) and the same raw response
// shape, so the HTTP call + DTO decoding live here once instead of being
// duplicated per caller.

protocol USDAFoodClient: Sendable {
    /// Searches FoodData Central. `dataTypes` are joined with "," exactly as
    /// USDA's `dataType` query param expects (e.g. ["Foundation", "SR Legacy"]).
    func search(
        query: String,
        dataTypes: [String],
        pageSize: Int,
        on req: Request
    ) async throws -> USDASearchRawResponse
}

enum USDAClientError: Error, Equatable {
    case tooManyRequests
    case upstreamError(UInt)
}

struct USDAAPIClient: USDAFoodClient {
    func search(
        query: String,
        dataTypes: [String],
        pageSize: Int,
        on req: Request
    ) async throws -> USDASearchRawResponse {
        let apiKey = Environment.get("USDA_API_KEY").flatMap { $0.isEmpty ? nil : $0 } ?? "DEMO_KEY"

        var uri = URI(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        uri.query = [
            "query=\(Self.percentEncode(query))",
            "pageSize=\(pageSize)",
            "dataType=\(Self.percentEncode(dataTypes.joined(separator: ",")))",
            "api_key=\(apiKey)",
        ].joined(separator: "&")

        let response = try await req.client.get(uri)
        switch response.status {
        case .ok:
            break
        case .tooManyRequests:
            throw USDAClientError.tooManyRequests
        default:
            req.logger.error("USDA search HTTP \(response.status.code)")
            throw USDAClientError.upstreamError(response.status.code)
        }
        return try response.content.decode(USDASearchRawResponse.self)
    }

    static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}

// MARK: - Raw USDA response DTOs

struct USDASearchRawResponse: Content {
    let foods: [Food]

    struct Food: Content {
        let fdcId: Int
        let description: String
        let dataType: String?
        let brandOwner: String?
        let brandName: String?
        let gtinUpc: String?
        let servingSize: Double?
        let servingSizeUnit: String?
        let foodNutrients: [Nutrient]?
    }

    struct Nutrient: Content {
        let nutrientId: Int?
        let value: Double?
    }
}
