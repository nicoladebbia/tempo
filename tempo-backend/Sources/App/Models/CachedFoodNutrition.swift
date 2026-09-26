import Fluent
import Foundation
import Vapor

// MARK: - CachedFoodNutrition

//
// Postgres cache for FoodNutritionResolver, keyed by normalized food
// description ("chicken breast, grilled" -> ...). One row per normalized
// query. Hits are cached effectively indefinitely (verified nutrition per
// 100g doesn't change); misses (no confident USDA match) are cached for 7
// days per the macro-engine spec, so an unresolvable AI-generated name
// doesn't hammer USDA on every retry. `expiresAt` carries both cases —
// FoodNutritionResolver picks the TTL when it writes a row.

final class CachedFoodNutrition: Model, Content, @unchecked Sendable {
    static let schema = "food_nutrition_cache"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "normalized_query")
    var normalizedQuery: String

    /// false = a cached miss (no confident match found last time).
    @Field(key: "is_hit")
    var isHit: Bool

    @OptionalField(key: "fdc_id")
    var fdcId: Int?

    @OptionalField(key: "description")
    var foodDescription: String?

    @OptionalField(key: "kcal")
    var kcal: Double?

    @OptionalField(key: "protein")
    var protein: Double?

    @OptionalField(key: "carbs")
    var carbs: Double?

    @OptionalField(key: "fat")
    var fat: Double?

    @OptionalField(key: "fiber")
    var fiber: Double?

    @OptionalField(key: "sugars")
    var sugars: Double?

    @OptionalField(key: "confidence")
    var confidence: Double?

    @Field(key: "expires_at")
    var expiresAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(normalizedQuery: String, resolved: ResolvedNutrition?, expiresAt: Date) {
        self.normalizedQuery = normalizedQuery
        self.expiresAt = expiresAt
        apply(resolved: resolved)
    }

    /// Overwrites the resolved-nutrition fields in place (used on cache
    /// refresh, e.g. re-resolving after a miss's TTL expires).
    func apply(resolved: ResolvedNutrition?) {
        isHit = resolved != nil
        fdcId = resolved?.fdcId
        foodDescription = resolved?.description
        kcal = resolved?.kcal
        protein = resolved?.protein
        carbs = resolved?.carbs
        fat = resolved?.fat
        fiber = resolved?.fiber
        sugars = resolved?.sugars
        confidence = resolved?.confidence
    }

    /// nil for a cached miss row.
    func toResolvedNutrition() -> ResolvedNutrition? {
        guard isHit,
              let fdcId, let foodDescription, let kcal, let protein, let carbs, let fat, let confidence
        else {
            return nil
        }
        return ResolvedNutrition(
            fdcId: fdcId,
            description: foodDescription,
            kcal: kcal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugars: sugars,
            confidence: confidence
        )
    }
}
