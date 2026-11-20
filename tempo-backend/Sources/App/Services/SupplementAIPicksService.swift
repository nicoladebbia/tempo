import Foundation
import Vapor

// MARK: - SupplementAIPicksService

//
// Fallback for (kind, name) combos NOT in the curated, human-researched
// catalog (SupplementCuratedCatalog.swift) — an unusual supplement the user
// actually owns, e.g. "L-Theanine" or "Turmeric". Uses AIFeatureRunner so it
// gets cache/circuit-breaker/budget-gate/retry for free, same as every other
// AI feature. Result is always `verified: false` — the app must show that
// honestly, per Nicola's "AI fallback only for unusual ones, clearly marked
// unverified" instruction.
//
// The prompt explicitly asks Claude to name only real, widely-sold products
// it's confident exist and to say plainly when it isn't sure about a
// certification — we never want it to invent a certification the way the
// curated catalog never does.

enum SupplementAIPicksService {
    static func picks(kind: String, name: String, on req: Request, bypassCache: Bool = false) async throws -> SupplementPicksDTO {
        let displayName = name.isEmpty ? kind : name
        let spec = AIFeatureSpec<SupplementPicksAIRawResponse>(
            model: AIConfig.haikuModel,
            maxTokens: 700,
            temperature: 0.2,
            timeout: AIConfig.haikuTimeout,
            estimatedInputTokens: 400,
            cacheKey: .supplementPicksAI(kind: kind, name: name)
        )
        let (raw, _) = try await AIFeatureRunner.run(
            spec: spec,
            on: req,
            bypassCache: bypassCache,
            buildPrompts: { (Self.systemPrompt, Self.buildUserPrompt(kind: kind, name: displayName)) },
            parse: { try Self.parseJSON($0) },
            fallback: { Self.fallbackRaw(name: displayName) }
        )
        return raw.toDTO(kind: kind)
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    You are a supplements buying guide. Given a supplement type (and possibly a specific product name a user already owns), suggest 2-3 REAL, WIDELY SOLD products in the United States that you are confident actually exist and are currently sold. Never invent a brand or product name.

    Prefer products with a genuine third-party certification: "NSF Certified for Sport", "Informed Sport", "Informed Choice", or "USP Verified". Only list a certification if you are reasonably confident it is accurate for that exact product — if you are not sure, omit the certifications array (leave it empty) rather than guessing. Be honest in `why` about your confidence.

    Output ONLY valid JSON, no markdown, no commentary, matching exactly:
    {
      "look_for": "one general buying-guidance sentence for this supplement type",
      "picks": [
        {
          "brand": "...",
          "product": "...",
          "form": "powder|capsule|tablet|gummy|liquid",
          "certifications": ["..."],
          "why": "one honest sentence",
          "approx_price_per_serving_usd": 0.30
        }
      ]
    }
    """

    private static func buildUserPrompt(kind: String, name: String) -> String {
        """
        Supplement type: \(kind)
        User's product name on their shelf: "\(name)"

        Suggest 2-3 real products for this. If the name above already names a specific real product, you may include it (if it's a real, sellable product) plus 1-2 alternatives.
        """
    }

    // MARK: - Parse

    private static func parseJSON(_ text: String) throws -> SupplementPicksAIRawResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonString: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonString = String(trimmed[start ... end])
        } else {
            jsonString = trimmed
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw SupplementAIPicksError.malformedResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SupplementPicksAIRawResponse.self, from: data)
    }

    private static func fallbackRaw(name _: String) -> SupplementPicksAIRawResponse {
        SupplementPicksAIRawResponse(
            lookFor: "Look for a reputable brand with third-party testing — NSF Certified for Sport, Informed Sport, or USP Verified — and check the certifier's own website to confirm.",
            picks: []
        )
    }
}

enum SupplementAIPicksError: Error {
    case malformedResponse
}

// MARK: - Raw Claude response

struct SupplementPicksAIRawResponse: Codable, Sendable {
    let lookFor: String
    let picks: [RawPick]

    struct RawPick: Codable, Sendable {
        let brand: String
        let product: String
        let form: String?
        let certifications: [String]?
        let why: String
        /// `Usd`, not `USD`: `.convertFromSnakeCase` turns `approx_price_per_serving_usd`
        /// into `approxPricePerServingUsd`, which is the only spelling that matches.
        let approxPricePerServingUsd: Double?
    }

    func toDTO(kind: String) -> SupplementPicksDTO {
        let mappedPicks = picks.map { pick in
            SupplementPicksDTO.Pick(
                brand: pick.brand,
                product: pick.product,
                form: pick.form,
                certifications: pick.certifications ?? [],
                why: pick.why,
                approxPricePerServingUSD: pick.approxPricePerServingUsd,
                priceAsOf: pick.approxPricePerServingUsd == nil ? nil : SupplementCuratedCatalog.priceAsOf,
                buyLinks: SupplementBuyLinks.make(brand: pick.brand, product: pick.product, brandURL: nil)
            )
        }
        return SupplementPicksDTO(kind: kind, picks: mappedPicks, verified: false, lookFor: lookFor)
    }
}
