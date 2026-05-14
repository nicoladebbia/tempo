//
// APIError.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

enum APIError: Error {
    case invalidURL
    case noResponse
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int)
    case decodingFailed(String)
    case networkError(String)
    case connectionRefused
    case notModified
    case timeout
    case unknown(statusCode: Int)
    /// Backend returned 402 with `code: "subscription_required"` — user needs Pro.
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §4.
    case subscriptionRequired
    /// Backend returned 402 with `code: "ai_consent_required"` — user has Pro
    /// but hasn't enabled AI data sharing in onboarding/settings.
    /// Per AI_INTELLIGENCE_ENGINE.md §11.3.
    case aiConsentRequired

    var userMessage: String {
        switch self {
        case .invalidURL:
            "Something went wrong. Please try again."
        case .noResponse:
            "No response from server. Check your connection."
        case .unauthorized:
            "Your session has expired. Please sign in again."
        case .forbidden:
            "You don't have permission to do that."
        case .notFound:
            "The requested data could not be found."
        case .conflict:
            "A conflict occurred. Please refresh and try again."
        case .rateLimited:
            "Too many requests. Please wait a moment."
        case .serverError:
            "Server error. We're working on it."
        case .notModified:
            "Data has not changed."
        case .decodingFailed:
            "Received unexpected data from the server."
        case .networkError:
            "Network error. Check your connection and try again."
        case .connectionRefused:
            "Cannot reach the server. Please try again later."
        case .timeout:
            "Request timed out. Please try again."
        case .unknown:
            "Something went wrong. Please try again."
        case .subscriptionRequired:
            "Pro subscription required to use AI features."
        case .aiConsentRequired:
            "Enable AI features in Settings to use this."
        }
    }

    /// Decodable wire shape for backend error responses produced by
    /// `TempoErrorMiddleware`. `code` is the typed identifier
    /// (e.g. "subscription_required", "ai_consent_required").
    struct TempoErrorBody: Decodable {
        let error: Bool?
        let reason: String?
        let code: String?
    }

    var isRetryable: Bool {
        switch self {
        case .serverError,
             .networkError,
             .timeout:
            true
        case .rateLimited:
            true
        case .connectionRefused:
            false
        default:
            false
        }
    }
}
