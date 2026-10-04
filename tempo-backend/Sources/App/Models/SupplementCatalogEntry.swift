import Fluent
import Foundation
import Vapor

// MARK: - Supplement Catalog Fluent Models

// The shared Tempo supplement catalog: anything one user reads off a label (or
// types in) is found by the next person's scan. See CreateSupplementCatalog for
// the anti-poisoning rules. `contributorID` is internal bookkeeping and is
// NEVER put on the wire.

final class SupplementCatalogEntry: Model, @unchecked Sendable {
    static let schema = "supplement_catalog_entries"

    @ID(key: .id)
    var id: UUID?

    /// "upc:<canonical UPC>" when the product has a barcode, else
    /// "name:<normalized brand>|<normalized name>". Unique.
    @Field(key: "entry_key")
    var entryKey: String

    @OptionalField(key: "upc")
    var upc: String?

    @OptionalField(key: "brand")
    var brand: String?

    @Field(key: "name")
    var name: String

    /// `SupplementKind.rawValue`.
    @Field(key: "kind")
    var kind: String

    @OptionalField(key: "dose_per_serving")
    var dosePerServing: String?

    @OptionalField(key: "servings_per_container")
    var servingsPerContainer: Double?

    @OptionalField(key: "protein_grams_per_serving")
    var proteinGramsPerServing: Double?

    @OptionalField(key: "calories_per_serving")
    var caloriesPerServing: Double?

    @OptionalField(key: "carbs_grams_per_serving")
    var carbsGramsPerServing: Double?

    @OptionalField(key: "fat_grams_per_serving")
    var fatGramsPerServing: Double?

    @Field(key: "ingredients")
    var ingredients: [String]

    /// "label_photo" | "manual".
    @Field(key: "origin")
    var origin: String

    /// The user who created the entry; the only one who may edit it. Nil once
    /// that account is deleted (the entry stays for everyone else).
    @OptionalField(key: "contributor_id")
    var contributorID: String?

    /// Distinct users who submitted or confirmed it (denormalized from
    /// `supplement_catalog_confirmations`).
    @Field(key: "confirmation_count")
    var confirmationCount: Int

    @Field(key: "created_at")
    var createdAt: Date

    @Field(key: "updated_at")
    var updatedAt: Date

    init() {}
}

/// One row per (entry, user): the distinct-user count that backs
/// `community_confirmations`. The contributor gets one at creation.
final class SupplementCatalogConfirmation: Model, @unchecked Sendable {
    static let schema = "supplement_catalog_confirmations"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "entry_id")
    var entryID: UUID

    @Field(key: "user_id")
    var userID: String

    @Field(key: "created_at")
    var createdAt: Date

    init() {}

    init(entryID: UUID, userID: String) {
        self.entryID = entryID
        self.userID = userID
        createdAt = Date()
    }
}
