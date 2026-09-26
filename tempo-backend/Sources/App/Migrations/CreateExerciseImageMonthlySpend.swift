import Fluent

// MARK: - CreateExerciseImageMonthlySpend

//
// Own table (deliberately not a column added to ai_monthly_spend / touched
// by AIBudgetTracker) — image generation cost is a flat 4c/image, not
// token-metered like the Claude calls that table tracks, and keeping it
// separate avoids touching AIBudgetTracker/AIMonthlySpend for an unrelated
// feature. Same shape/upsert pattern as ai_monthly_spend (one row per
// calendar month, atomic INSERT ... ON CONFLICT increment).

struct CreateExerciseImageMonthlySpend: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("exercise_image_monthly_spend")
            .field("year_month", .string, .identifier(auto: false))
            .field("spend_cents", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("exercise_image_monthly_spend").delete()
    }
}
