//
// APIError.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case noResponse
    case unauthorized
    case forbidden
    case notFound
    case conflict
    /// Backend returned 413 — the request body exceeded the server's size
    /// limit. For receipt/photo uploads this means the image wasn't
    /// downsampled enough; the caller should shrink the payload and retry,
    /// not surface a generic "something went wrong".
    case payloadTooLarge
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
    /// Backend returned 402 with `code: "program_import_quota"` — a free
    /// user has used their monthly Trainer Program import allowance.
    /// Carries the structured quota fields so the import screen can show
    /// "X of Y used, resets on Z" without a second round-trip.
    case programImportQuotaExceeded(limit: Int, used: Int, resetsAt: Date)

    var userMessage: String {
        switch self {
        case .invalidURL:
            String(localized: "Something went wrong. Please try again.")
        case .noResponse:
            String(localized: "No response from server. Check your connection.")
        case .unauthorized:
            String(localized: "Your session has expired. Please sign in again.")
        case .forbidden:
            String(localized: "You don't have permission to do that.")
        case .notFound:
            String(localized: "The requested data could not be found.")
        case .conflict:
            String(localized: "A conflict occurred. Please refresh and try again.")
        case .payloadTooLarge:
            String(localized: "That image is too large to upload. Try a tighter crop of the receipt.")
        case .rateLimited:
            String(localized: "Too many requests. Please wait a moment.")
        case .serverError:
            String(localized: "Server error. We're working on it.")
        case .notModified:
            String(localized: "Data has not changed.")
        case .decodingFailed:
            String(localized: "Received unexpected data from the server.")
        case .networkError:
            String(localized: "Network error. Check your connection and try again.")
        case .connectionRefused:
            String(localized: "Cannot reach the server. Please try again later.")
        case .timeout:
            String(localized: "Request timed out. Please try again.")
        case .unknown:
            String(localized: "Something went wrong. Please try again.")
        case .subscriptionRequired:
            String(localized: "Pro subscription required to use AI features.")
        case .aiConsentRequired:
            String(localized: "Enable AI features in Settings to use this.")
        case let .programImportQuotaExceeded(limit, _, _):
            String(localized: "You've used your \(limit) free trainer-program imports this month.")
        }
    }

    /// Without this, `localizedDescription` reads "(Tempo.APIError error 3.)".
    var errorDescription: String? {
        userMessage
    }

    /// Decodable wire shape for backend error responses produced by
    /// `TempoErrorMiddleware`. `code` is the typed identifier
    /// (e.g. "subscription_required", "ai_consent_required").
    struct TempoErrorBody: Decodable {
        let error: Bool?
        let reason: String?
        let code: String?
    }

    /// Decodable wire shape for the Trainer Program import quota 402
    /// (`code: "program_import_quota"`) — a superset of `TempoErrorBody`
    /// with the extra fields `TrainingProgramImportController` sends.
    struct ProgramImportQuotaErrorBody: Decodable {
        let code: String?
        let limit: Int?
        let used: Int?
        let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case code
            case limit
            case used
            case resetsAt = "resets_at"
        }
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
