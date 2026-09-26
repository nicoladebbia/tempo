import Fluent

// MARK: - Create Food Nutrition Cache Migration

//
// Backs FoodNutritionResolver's Postgres cache (Sources/App/Nutrition/).
// One row per normalized food description; `unique(on:)` doubles as the
// upsert lookup index for the resolver's hot path.

struct CreateFoodNutritionCache: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("food_nutrition_cache")
            .id()
            .field("normalized_query", .string, .required)
            .field("is_hit", .bool, .required)
            .field("fdc_id", .int)
            .field("description", .string)
            .field("kcal", .double)
            .field("protein", .double)
            .field("carbs", .double)
            .field("fat", .double)
            .field("fiber", .double)
            .field("sugars", .double)
            .field("confidence", .double)
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .unique(on: "normalized_query")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("food_nutrition_cache").delete()
    }
}
