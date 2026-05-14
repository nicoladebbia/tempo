//
// NutritionProxyDTOs.swift
// Tempo
//
// iOS-side DTOs + endpoint definitions for the generic nutrition Claude proxy
// on the backend (POST /v1/nutrition/ai/proxy/text and .../proxy/vision).
//
// The proxy moves all nutrition AI Claude calls server-side so the Anthropic
// API key never ships in the app binary. Per ADR-018 + INTELLIGENCE_REMEDIATION_PLAN.md §3.
//

import Foundation

// MARK: - Text proxy request / response

/// Mirrors backend `NutritionProxyTextRequest` (snake_case wire format).
struct NutritionProxyTextRequest: Codable, Sendable {
    /// One of: "haiku", "sonnet". Backend rejects anything else (Opus is
    /// reserved for pattern detection per AI spec §1).
    let model: String
    let system: String
    let userMessage: String
    let maxTokens: Int
    let temperature: Double
    /// Short tag for backend logs — e.g. "meal_plan", "meal_recipe", "coach".
    let caller: String

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case userMessage = "user_message"
        case maxTokens = "max_tokens"
        case temperature
        case caller
    }
}

/// Mirrors backend `NutritionProxyVisionRequest`. Used by PhotoAnalysisService.
struct NutritionProxyVisionRequest: Codable, Sendable {
    let model: String
    let system: String
    let userMessage: String
    /// e.g. "image/jpeg", "image/png", "image/webp"
    let imageMediaType: String
    /// Base64-encoded image bytes (no data: prefix).
    let imageBase64: String
    let maxTokens: Int
    let temperature: Double
    let caller: String

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case userMessage = "user_message"
        case imageMediaType = "image_media_type"
        case imageBase64 = "image_base64"
        case maxTokens = "max_tokens"
        case temperature
        case caller
    }
}

/// Mirrors backend `NutritionProxyTextResponse`. The backend strips the
/// surrounding Envelope before this is decoded (see APIClient).
struct NutritionProxyTextResponse: Codable, Sendable {
    let text: String
}

// MARK: - APIEndpoint extensions

extension APIEndpoint where Response == NutritionProxyTextResponse {
    static func nutritionProxyText() -> Self {
        APIEndpoint(path: "/v1/nutrition/ai/proxy/text", method: .post)
    }

    static func nutritionProxyVision() -> Self {
        APIEndpoint(path: "/v1/nutrition/ai/proxy/vision", method: .post)
    }
}
