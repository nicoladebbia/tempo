//
// APIEndpoints+GroceryShare.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation

// MARK: - GroceryShareItemUpsertDTO

//
// Mirror the backend wire shapes in GroceryShareController.swift
// (feat/grocery-share-order). The backend uses
// `ContentConfiguration.global` with `.convertToSnakeCase` /
// `.convertFromSnakeCase`, but this app's APIClient decoder has NO key
// strategy — so every property whose snake_case wire form differs from a
// literal lowercase spelling needs an explicit CodingKeys entry here.

struct GroceryShareItemUpsertDTO: Codable, Sendable {
    let id: String
    var name: String
    var quantity: Double
    var unit: String
    var category: String
    var checked: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case quantity
        case unit
        case category
        case checked
        case updatedAt = "updated_at"
    }
}

// MARK: - GroceryShareUpsertRequestDTO

struct GroceryShareUpsertRequestDTO: Codable, Sendable {
    /// nil on first share; the existing token on a re-push/replace.
    var token: String?
    var title: String
    var store: String?
    var items: [GroceryShareItemUpsertDTO]
}

// MARK: - GroceryShareItemDTO

struct GroceryShareItemDTO: Codable, Sendable {
    let id: String
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let checked: Bool
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case quantity
        case unit
        case category
        case checked
        case updatedAt = "updated_at"
    }
}

// MARK: - GroceryShareDTO

struct GroceryShareDTO: Codable, Sendable {
    let token: String
    let url: String
    let title: String
    let store: String?
    let expiresAt: Date
    let revoked: Bool
    let items: [GroceryShareItemDTO]

    enum CodingKeys: String, CodingKey {
        case token
        case url
        case title
        case store
        case revoked
        case items
        case expiresAt = "expires_at"
    }
}

extension APIEndpoint where Response == GroceryShareDTO {
    /// `PUT /v1/grocery/shared` — create a new share (no `token` in the
    /// request body) or replace an existing one's snapshot (`token` set).
    static func upsertGroceryShare() -> Self {
        APIEndpoint(path: "/v1/grocery/shared", method: .put)
    }

    /// `GET /v1/grocery/shared/:token` — owner-side read of current state
    /// (used to pull shopper ticks back into the app).
    static func getGroceryShare(token: String) -> Self {
        APIEndpoint(path: "/v1/grocery/shared/\(token)", method: .get)
    }
}

extension APIEndpoint where Response == EmptyResponse {
    /// `POST /v1/grocery/shared/:token/revoke` — kills the public link.
    /// Backend returns `Envelope<EmptyResponse>`, but APIClient special-cases
    /// `T == EmptyResponse` and returns without decoding the body at all, so
    /// `expectsEnvelope` is moot here — left at its default.
    static func revokeGroceryShare(token: String) -> Self {
        APIEndpoint(path: "/v1/grocery/shared/\(token)/revoke", method: .post)
    }
}

// MARK: - InstacartCartItemWireDTO

struct InstacartCartItemWireDTO: Codable, Sendable {
    let name: String
    var quantity: Double?
    var unit: String?
}

// MARK: - InstacartCartRequestDTO

struct InstacartCartRequestDTO: Codable, Sendable {
    var title: String?
    var items: [InstacartCartItemWireDTO]
}

// MARK: - InstacartCartResponseDTO

struct InstacartCartResponseDTO: Codable, Sendable {
    let url: String
}

extension APIEndpoint where Response == InstacartCartResponseDTO {
    /// `POST /v1/grocery/instacart-cart`. Throws `APIError.unknown(statusCode: 412)`
    /// when the backend has no `INSTACART_API_KEY` configured — callers treat
    /// ANY failure here (not just 412) as "fall back to per-item search
    /// links", since APIClient doesn't currently surface the 412 body's
    /// `instacart_not_configured` code past a generic `.unknown` case.
    static func createInstacartCart() -> Self {
        APIEndpoint(path: "/v1/grocery/instacart-cart", method: .post)
    }
}
