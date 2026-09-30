//
// ReceiptAliasSyncDTOs.swift
// Tempo
//
// Wire types for the backend's crowd-sourced receipt-alias table
// (POST /v1/nutrition/receipt-aliases/confirm — see
// tempo-backend/Sources/App/Controllers/ReceiptItemAliasController.swift).
// The LOCAL alias layer (ReceiptItemResolver.learn, SwiftData
// ReceiptItemAlias) always wins immediately for this device; this call is a
// best-effort, fire-and-forget contribution to the shared crowd table so
// other users' devices benefit too. Per the backend's own doc comment,
// callers should treat this endpoint as silently skippable if unreachable —
// never block or surface an error to the user over it.
//

import Foundation

// MARK: - ReceiptAliasConfirmRequest

struct ReceiptAliasConfirmRequest: Codable, Sendable {
    let storeChain: String
    let rawText: String
    let expandedName: String
    let canonicalFoodName: String
    let barcode: String?

    enum CodingKeys: String, CodingKey {
        case storeChain = "store_chain"
        case rawText = "raw_text"
        case expandedName = "expanded_name"
        case canonicalFoodName = "canonical_food_name"
        case barcode
    }
}

// MARK: - ReceiptAliasConfirmResponse

struct ReceiptAliasConfirmResponse: Codable, Sendable {
    let expandedName: String
    let canonicalFoodName: String
    let barcode: String?
    let isTrusted: Bool
    let confirmationCount: Int

    enum CodingKeys: String, CodingKey {
        case expandedName = "expanded_name"
        case canonicalFoodName = "canonical_food_name"
        case barcode
        case isTrusted = "is_trusted"
        case confirmationCount = "confirmation_count"
    }
}

// MARK: - APIEndpoint extension

extension APIEndpoint where Response == ReceiptAliasConfirmResponse {
    static func receiptAliasConfirm() -> Self {
        APIEndpoint(path: "/v1/nutrition/receipt-aliases/confirm", method: .post)
    }
}
