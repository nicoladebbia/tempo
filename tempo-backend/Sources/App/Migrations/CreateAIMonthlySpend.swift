import Fluent
import SQLKit

// MARK: - Create AI Monthly Spend Migration
//
// Per AI_INTELLIGENCE_ENGINE.md §5.4 + INTELLIGENCE_REMEDIATION_PLAN.md §5.
//
// Backs the AIBudgetTracker actor. One row per month. spend_cents accumulates
// every Claude call across every route (insights + nutrition AI proxy).
// Survives process restarts and is shared across multiple Vapor instances.

struct CreateAIMonthlySpend: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("ai_monthly_spend")
            // Format: "YYYY-MM" (e.g. "2026-05"). Primary key.
            .field("year_month", .string, .identifier(auto: false))
            .field("spend_cents", .int, .required, .sql(.default(0)))
            // Highest threshold action level already applied this month.
            // 0 = none, 50/80/95/100 = corresponding ladder rung from spec §5.4.
            // Persisted so a process restart doesn't re-fire the warning.
            .field("threshold_applied", .int, .required, .sql(.default(0)))
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("ai_monthly_spend").delete()
    }
}
