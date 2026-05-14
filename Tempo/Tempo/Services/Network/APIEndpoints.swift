//
// APIEndpoints.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

// MARK: - HTTPMethod

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - APIEndpoint

struct APIEndpoint<Response: Decodable & Sendable> {
    let path: String
    let method: HTTPMethod
    let requiresAuth: Bool
    /// True when the backend wraps the response in `Envelope<T>` (the default for
    /// most routes per VAPOR_PROJECT_STRUCTURE.md). False for the small set of
    /// auth routes that return their payload directly. Per
    /// INTELLIGENCE_REMEDIATION_PLAN.md §3 (envelope unwrap fix).
    let expectsEnvelope: Bool

    init(path: String, method: HTTPMethod = .get, requiresAuth: Bool = true, expectsEnvelope: Bool = true) {
        self.path = path
        self.method = method
        self.requiresAuth = requiresAuth
        self.expectsEnvelope = expectsEnvelope
    }
}

// MARK: - APIEnvelope

/// Mirrors backend `Envelope<T>` ({ ok, data, meta, pagination? }). The iOS
/// APIClient unwraps this automatically when `APIEndpoint.expectsEnvelope` is
/// true and hands the caller the inner `T`. Per
/// INTELLIGENCE_REMEDIATION_PLAN.md §3.
struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let ok: Bool
    let data: T
}

// MARK: - Auth Endpoints

extension APIEndpoint where Response == AuthTokenResponse {
    static func signInWithApple() -> Self {
        // Auth controller returns AuthTokenResponse directly (no Envelope wrap).
        APIEndpoint(path: "/v1/auth/apple", method: .post, requiresAuth: false, expectsEnvelope: false)
    }

    static func refreshToken() -> Self {
        APIEndpoint(path: "/v1/auth/refresh", method: .post, requiresAuth: false, expectsEnvelope: false)
    }
}

extension APIEndpoint where Response == EmptyResponse {
    static func logout() -> Self {
        // Auth controller returns LogoutResponse directly; iOS decodes as Empty.
        APIEndpoint(path: "/v1/auth/logout", method: .post, requiresAuth: true, expectsEnvelope: false)
    }
}

// MARK: - Sync Endpoints

extension APIEndpoint where Response == SyncStatusResponse {
    static func syncStatus() -> Self {
        APIEndpoint(path: "/v1/sync/status", method: .get)
    }
}

extension APIEndpoint where Response == SyncBatchResponse {
    static func syncBatch() -> Self {
        APIEndpoint(path: "/v1/sync/batch", method: .post)
    }
}

// MARK: - AuthTokenResponse

struct AuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
}

// MARK: - SyncStatusResponse

struct SyncStatusResponse: Codable {
    let last_synced: [String: String]
}

// MARK: - SyncBatchResponse

struct SyncBatchResponse: Codable {
    let succeeded: Int
    let failed: Int
}

// MARK: - EmptyResponse

struct EmptyResponse: Codable {}

// MARK: - User endpoints

/// Mirrors backend AIConsentRequest. Per AI_INTELLIGENCE_ENGINE.md §11.3.
struct AIConsentRequestDTO: Codable, Sendable {
    let consented: Bool
}

/// Mirrors backend AIConsentResponse.
struct AIConsentResponseDTO: Codable, Sendable {
    let aiConsentAt: Date?

    enum CodingKeys: String, CodingKey {
        case aiConsentAt = "ai_consent_at"
    }
}

extension APIEndpoint where Response == AIConsentResponseDTO {
    static func setAIConsent() -> Self {
        APIEndpoint(path: "/v1/user/ai-consent", method: .post)
    }
}

/// Mirrors backend UserMeResponse. Used to hydrate Pro tier + AI consent state
/// after sign-in. Per INTELLIGENCE_REMEDIATION_PLAN.md §4.
struct UserMeResponseDTO: Codable, Sendable {
    let id: String
    let displayName: String
    let username: String
    let timezone: String
    let xpTotal: Int
    let level: Int
    let streakDays: Int
    let isPro: Bool
    let productId: String?
    let subscriptionExpiresAt: Date?
    let aiConsentAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case username
        case timezone
        case xpTotal = "xp_total"
        case level
        case streakDays = "streak_days"
        case isPro = "is_pro"
        case productId = "product_id"
        case subscriptionExpiresAt = "subscription_expires_at"
        case aiConsentAt = "ai_consent_at"
    }
}

extension APIEndpoint where Response == UserMeResponseDTO {
    static func currentUser() -> Self {
        APIEndpoint(path: "/v1/user/me", method: .get)
    }
}
