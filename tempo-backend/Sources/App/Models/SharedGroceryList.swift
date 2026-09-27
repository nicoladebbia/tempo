import Fluent
import Foundation
import Vapor

// MARK: - SharedGroceryList

//
// Backs the public "live shared grocery list" feature (feat/grocery-share-order,
// Lane C). One row per share link a user creates from a GroceryList. `token`
// is the unguessable (160-bit) URL-safe identifier used by the PUBLIC,
// unauthenticated /g/:token routes (PublicGroceryShareController) — never
// expose the numeric `id` publicly, only `token`. The owner-side (JWT
// authenticated) routes live in GroceryShareController at
// /v1/grocery/shared.
//
// `itemsJSON` is a JSON-encoded array of `SharedGroceryItemSnapshot` — plain
// string storage (same pattern as WeeklyPlanJobRecord.requestJSON/planJSON)
// rather than a child table, since the whole snapshot is always read/written
// together and there's no need to query into individual items server-side.

final class SharedGroceryList: Model, Content, @unchecked Sendable {
    static let schema = "shared_grocery_lists"

    @ID(key: .id)
    var id: UUID?

    /// Owning user. Never exposed on the public page/API — GroceryShareDTO
    /// carries only token/title/store/items.
    @Field(key: "user_id")
    var userID: String

    @Field(key: "token")
    var token: String

    @Field(key: "title")
    var title: String

    @OptionalField(key: "store")
    var store: String?

    /// JSON-encoded `[SharedGroceryItemSnapshot]`.
    @Field(key: "items_json")
    var itemsJSON: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "revoked")
    var revoked: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: String,
        token: String,
        title: String,
        store: String? = nil,
        itemsJSON: String,
        expiresAt: Date
    ) {
        self.id = id
        self.userID = userID
        self.token = token
        self.title = title
        self.store = store
        self.itemsJSON = itemsJSON
        self.expiresAt = expiresAt
        revoked = false
    }

    /// A shopper-visible link is only live when neither revoked nor expired.
    var isLive: Bool {
        !revoked && expiresAt > Date()
    }
}

// MARK: - Item snapshot

//
// One line item as stored in `items_json`. `updatedAt` is the LWW merge
// clock for `checked` only — catalog fields (name/quantity/unit/category)
// always take the owner's latest push (only the owner edits list contents;
// a shopper can only toggle `checked`). See GroceryShareController's merge
// logic and PublicGroceryShareController.toggleItem (server-stamped, never
// client-supplied, since that endpoint is unauthenticated).

struct SharedGroceryItemSnapshot: Codable, Sendable, Equatable {
    let id: String
    var name: String
    var quantity: Double
    var unit: String
    var category: String
    var checked: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, category, checked
        case updatedAt = "updated_at"
    }
}

// MARK: - JSON (de)serialization for `items_json`

//
// Deliberately a private, from-scratch encoder/decoder (ISO8601 dates, no
// key strategy) rather than ContentConfiguration.global — this JSON never
// goes over the wire directly, it's just how the array is stored as a
// single TEXT column, so it must be internally consistent with itself only.

extension SharedGroceryList {
    private static let itemsEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let itemsDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func decodedItems() -> [SharedGroceryItemSnapshot] {
        guard let data = itemsJSON.data(using: .utf8) else { return [] }
        return (try? Self.itemsDecoder.decode([SharedGroceryItemSnapshot].self, from: data)) ?? []
    }

    static func encodeItems(_ items: [SharedGroceryItemSnapshot]) throws -> String {
        let data = try itemsEncoder.encode(items)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
