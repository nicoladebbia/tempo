import Fluent

// MARK: - Add Micronutrients to Food Nutrition Cache

//
// Per-100g vitamins/minerals/fats from USDA, stored as a JSON object keyed by
// `Nutrient.rawValue`. Nullable on purpose: rows cached before this migration
// have NULL and FoodNutritionResolver refreshes them once on next lookup.

struct AddMicrosToFoodNutritionCache: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("food_nutrition_cache")
            .field("micros", .json)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("food_nutrition_cache")
            .deleteField("micros")
            .update()
    }
}
