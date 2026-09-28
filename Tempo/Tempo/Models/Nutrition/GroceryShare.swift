//
// GroceryShare.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation
import SwiftData

// MARK: - GroceryShare

//
// Local record of a "live shared grocery list" link created from a
// GroceryList (feat/grocery-share-order, Lane C). Deliberately its own
// model rather than new fields on GroceryList — one GroceryList can only
// ever have zero or one active share, and nothing else in the app needs to
// read share state, so keeping it separate avoids widening the shared
// GroceryList model that GroceryListView/GroceryListGenerator own.
//
// `itemStateJSON` is the LAST-SYNCED baseline for each item's
// (checked, updatedAt) pair — NOT the current in-app state. SharedGroceryListService
// diffs the live GroceryListItem rows against this baseline to decide which
// items actually changed locally since the last push, so it only bumps an
// item's timestamp when its checked value truly changed here (see
// SharedGroceryListService.push). Without this, every debounced push would
// stamp every item "now", and a stale owner push could clobber a shopper's
// more recent tick on the server (the server does last-write-wins by
// timestamp — GroceryShareControllerTests.staleOwnerPushDoesNotClobberNewerShopperTick
// on the backend).

@Model
final class GroceryShare {
    @Attribute(.unique)
    var listID: UUID

    /// Unguessable token from the backend — same value embedded in `url`.
    var token: String

    /// Full shopper-facing URL (`<publicBaseURL>/g/<token>`), ready for
    /// ShareLink/openURL — never rebuilt client-side.
    var url: String

    var createdAt: Date

    var expiresAt: Date

    /// Set true after the owner taps "Stop sharing" or the backend reports
    /// the share as revoked/expired on a pull. Once true,
    /// SharedGroceryListService stops pushing/pulling for this list.
    var revoked: Bool

    /// JSON-encoded `[GroceryShareItemState]` — the last-synced baseline.
    var itemStateJSON: String

    init(
        listID: UUID,
        token: String,
        url: String,
        createdAt: Date = Date(),
        expiresAt: Date,
        revoked: Bool = false,
        itemStateJSON: String = "[]"
    ) {
        self.listID = listID
        self.token = token
        self.url = url
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.revoked = revoked
        self.itemStateJSON = itemStateJSON
    }

    /// Live from the local point of view — mirrors `SharedGroceryList.isLive`
    /// on the backend, so the UI/service can decide to stop syncing without
    /// a round trip when the 14-day window has obviously passed.
    var isLive: Bool {
        !revoked && expiresAt > Date()
    }
}

// MARK: - GroceryShareItemState

/// One item's last-synced baseline. `id` matches `GroceryListItem.id.uuidString`
/// — the stable identifier both the app and the shopper's page key off of.
struct GroceryShareItemState: Codable, Equatable, Sendable {
    let id: String
    var checked: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case checked
        case updatedAt = "updated_at"
    }
}

// MARK: - JSON (de)serialization for `itemStateJSON`

//
// A private, from-scratch encoder/decoder (ISO8601 dates, no key strategy),
// matching the backend's `SharedGroceryList.itemsJSON` convention — this
// value never crosses the network directly, it's just how the baseline
// array is packed into one SwiftData column.

extension GroceryShare {
    private static let stateEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let stateDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func decodedItemState() -> [GroceryShareItemState] {
        guard let data = itemStateJSON.data(using: .utf8) else {
            return []
        }
        return (try? Self.stateDecoder.decode([GroceryShareItemState].self, from: data)) ?? []
    }

    static func encodeItemState(_ items: [GroceryShareItemState]) -> String {
        guard let data = try? stateEncoder.encode(items),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }
}
