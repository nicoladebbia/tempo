import Fluent
import SQLKit

// MARK: - Add Coach Spend to AI Monthly Spend
//
// Per Coach v2.1 plan §04-ai-architecture.md "Cost ceilings". Adds a
// `coach_spend_cents` column to the existing monthly-aggregate row so the
// budget tracker can enforce a per-feature sub-cap for caller="coach"
// alongside the global cap.
//
// Default value 0 ensures the migration is safe to ship without backfill —
// the next coach call upserts the field via the same SQL pattern as
// spend_cents.

struct AddCoachSpendToAIMonthlySpend: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("ai_monthly_spend")
            .field("coach_spend_cents", .int, .required, .sql(.default(0)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("ai_monthly_spend")
            .deleteField("coach_spend_cents")
            .update()
    }
}
