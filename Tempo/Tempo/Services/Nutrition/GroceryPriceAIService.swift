//
// GroceryPriceAIService.swift
// Tempo
//
// AI fallback for grocery item pricing (BUILD item 4, price source (2)).
// Called only for items GroceryPriceEstimator.resolveFromHistory and the
// local GroceryPriceCache couldn't price — ALL of them batched into ONE
// Haiku call via the existing nutrition proxy (mirrors VoicePantryService's
// send/parse pattern) rather than one call per item. Results are cached
// locally (GroceryPriceCache) so the same batch isn't re-paid on every
// list render.
//
// Also generates the (optional, simple) "cheaper swaps" suggestions shown
// when the list is over budget.
//

import Foundation
import os

// MARK: - EstimatedPriceItem

private struct EstimatedPriceItem: Decodable, Sendable {
    let name: String
    let priceUSD: Double

    enum CodingKeys: String, CodingKey {
        case name
        case priceUSD = "price_usd"
    }
}

// MARK: - EstimatedPriceResponse

private struct EstimatedPriceResponse: Decodable, Sendable {
    let items: [EstimatedPriceItem]
}

// MARK: - CheaperSwapsResponse

private struct CheaperSwapsResponse: Decodable, Sendable {
    let swaps: [String]
}

// MARK: - GroceryPriceAIError

enum GroceryPriceAIError: LocalizedError {
    case emptyRequest
    case apiFailed(Error)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyRequest: "Nothing to price."
        case let .apiFailed(error): "Couldn't reach the assistant: \(error.localizedDescription)"
        case let .parseFailed(detail): "Couldn't read the assistant's reply: \(detail)"
        }
    }
}

// MARK: - GroceryPriceAIService

@Observable
@MainActor
final class GroceryPriceAIService {
    private let apiClient: APIClient
    private let logger = Logger(subsystem: "app.tempo", category: "grocery-price-ai")

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    /// One batched call pricing every name in `names` at `store`. Returns a
    /// dictionary keyed by the EXACT input name (lowercased) so callers can
    /// look up by the same key they sent. Items the model skips (or the
    /// whole call failing) simply aren't in the result — callers leave those
    /// items unpriced rather than fabricating a number.
    func estimatePrices(names: [String], store: GroceryStore) async throws -> [String: Double] {
        let unique = Array(Set(names.map { $0.lowercased() })).sorted()
        guard !unique.isEmpty else {
            throw GroceryPriceAIError.emptyRequest
        }

        let storeContext = store == .generic
            ? "a typical US grocery store"
            : store.displayName
        let itemList = unique.map { "\"\($0)\"" }.joined(separator: ", ")
        let prompt = """
        Estimate the typical current US grocery price for each of these items \
        at \(storeContext): [\(itemList)].

        Return JSON only in this exact shape:
        {"items":[{"name":"","price_usd":0}]}.

        Rules:
        - "name" must exactly match one of the input names (same casing).
        - "price_usd" is your best-guess TOTAL price for the quantity implied \
        by the name as given (e.g. "3 breasts" prices 3 breasts, not 1). Use a \
        plain number, no currency symbol.
        - Include every item from the input list, in any order.
        """

        let text = try await send(
            system: Self.priceSystemPrompt,
            prompt: prompt,
            maxTokens: 2000,
            feature: "grocery_price_estimate"
        )
        let parsed: EstimatedPriceResponse = try parseJSON(text, as: EstimatedPriceResponse.self, feature: "grocery_price_estimate")
        var result: [String: Double] = [:]
        for item in parsed.items where item.priceUSD > 0 {
            result[item.name.lowercased()] = item.priceUSD
        }
        return result
    }

    /// Short list of cheaper-swap suggestions when the list is over budget.
    /// Deliberately simple — a few plain-language bullet strings, not a
    /// structured substitution engine.
    func suggestCheaperSwaps(items: [String], overBy: Double, store: GroceryStore) async throws -> [String] {
        guard !items.isEmpty else {
            throw GroceryPriceAIError.emptyRequest
        }
        let storeContext = store == .generic ? "a typical US grocery store" : store.displayName
        let itemList = items.map { "\"\($0)\"" }.joined(separator: ", ")
        let prompt = """
        This grocery list at \(storeContext) is about $\(String(format: "%.0f", overBy)) over budget: \
        [\(itemList)].

        Return JSON only in this exact shape: {"swaps":["",""]}.

        Rules:
        - 2–4 short, concrete suggestions (e.g. "Swap salmon for tilapia — \
        save ~$8"). Each under 12 words.
        - Suggest cheaper equivalents or smaller pack sizes from the SAME list, \
        not unrelated advice.
        """

        let text = try await send(
            system: Self.swapsSystemPrompt,
            prompt: prompt,
            maxTokens: 500,
            feature: "grocery_cheaper_swaps"
        )
        let parsed: CheaperSwapsResponse = try parseJSON(text, as: CheaperSwapsResponse.self, feature: "grocery_cheaper_swaps")
        return parsed.swaps
    }

    // MARK: - Prompts

    private static let priceSystemPrompt = """
    You are Tempo's grocery price estimator. Given a list of food item names \
    and a store, output your best-guess typical US retail price for each as \
    JSON only — no prose, no markdown fences.
    """

    private static let swapsSystemPrompt = """
    You are Tempo's drill-sergeant grocery coach. Given an over-budget \
    shopping list, suggest a few blunt, concrete cheaper swaps. Output JSON \
    only — no prose, no markdown fences.
    """

    // MARK: - Proxy call (mirrors VoicePantryService.send)

    private func send(system: String, prompt: String, maxTokens: Int, feature: String) async throws -> String {
        do {
            let body = NutritionProxyTextRequest(
                model: "haiku",
                system: system,
                userMessage: prompt,
                maxTokens: maxTokens,
                temperature: 0.2,
                caller: feature
            )
            let response: NutritionProxyTextResponse = try await apiClient.request(
                APIEndpoint<NutritionProxyTextResponse>.nutritionProxyText(),
                body: body
            )
            logger.info("[\(feature)] Haiku response received")
            return response.text
        } catch {
            logger.error("[\(feature)] proxy error: \(String(describing: error))")
            throw GroceryPriceAIError.apiFailed(error)
        }
    }

    // MARK: - JSON parsing (same extraction strategy as VoicePantryService)

    private func parseJSON<T: Decodable>(_ response: String, as type: T.Type, feature: String) throws -> T {
        let decoder = JSONDecoder()
        let cleaned = VoicePantryService.stripMarkdownFence(response)

        if let data = cleaned.data(using: .utf8), let result = try? decoder.decode(T.self, from: data) {
            return result
        }
        if let startIndex = cleaned.firstIndex(of: "{"),
           let endIndex = cleaned.lastIndex(of: "}"),
           startIndex < endIndex
        {
            let jsonString = String(cleaned[startIndex ... endIndex])
            if let data = jsonString.data(using: .utf8),
               let result = try? decoder.decode(T.self, from: data)
            {
                return result
            }
        }
        logger.error("[\(feature)] parse failed: \(response.prefix(200))")
        throw GroceryPriceAIError.parseFailed("unrecognized response shape")
    }
}
