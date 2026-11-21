//
// FoodSearchService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import os
import SwiftData

// MARK: - FoodSearchServiceProtocol

protocol FoodSearchServiceProtocol: Sendable {
    func searchUSDA(query: String) async throws -> [FoodSearchResult]
}

// MARK: - FoodSearchService

@Observable
final class FoodSearchService: FoodSearchServiceProtocol, @unchecked Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = Logger.nutrition

    /// USDA FoodData Central API key.
    /// Reads from Info.plist key USDA_API_KEY, falls back to demo key.
    private let usdaAPIKey: String

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()

        if let key = Bundle.main.infoDictionary?["USDA_API_KEY"] as? String, !key.isEmpty {
            usdaAPIKey = key
        } else {
            // USDA provides a demo key with lower limits — acceptable for development.
            usdaAPIKey = "DEMO_KEY"
        }
    }

    // MARK: - USDA Search

    // USDA FoodData Central API: https://fdc.nal.usda.gov/api-guide.html
    // Rate limit: 1000 requests/hour per API key.

    func searchUSDA(query: String) async throws -> [FoodSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: usdaAPIKey),
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "pageSize", value: "25"),
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded"),
        ]

        guard let url = components.url else {
            throw NutritionError.searchFailed("Invalid search URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NutritionError.searchFailed("No HTTP response")
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                break
            case 429:
                let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    .flatMap { TimeInterval($0) }
                throw NutritionError.rateLimited(retryAfter: retryAfter)
            default:
                throw NutritionError.searchFailed("USDA returned status \(httpResponse.statusCode)")
            }

            let fdcResponse = try decoder.decode(FdcSearchResponse.self, from: data)
            let results = fdcResponse.foods.map { $0.toFoodSearchResult() }
            logger.info("USDA search '\(trimmed)': \(results.count) results")
            return results
        } catch let error as NutritionError {
            throw error
        } catch {
            logger.error("USDA search failed: \(error.localizedDescription)")
            throw NutritionError.searchFailed(error.localizedDescription)
        }
    }

    // MARK: - Barcode Lookup (OpenFoodFacts)

    // OpenFoodFacts API: https://world.openfoodfacts.org/data
    // Rate limit: 100 requests/minute for product GET.
    // Required: User-Agent header per OFF terms of use.

    // MARK: - Local Search (SwiftData)

    // MARK: - Cache Food

}
