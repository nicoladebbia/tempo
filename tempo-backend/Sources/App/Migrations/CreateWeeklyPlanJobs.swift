import Fluent
import SQLKit

// MARK: - CreateWeeklyPlanJobs

//
// Backs the server-side weekly meal-plan job (WeeklyPlanController +
// WeeklyPlanJob). One row per "build next week" attempt. Index on
// (user_id, created_at DESC) — `latest` and the duplicate-in-flight check
// both query "this user's jobs, newest first".

struct CreateWeeklyPlanJobs: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("weekly_plan_jobs")
            .id()
            .field("user_id", .string, .required, .references("users", "id", onDelete: .cascade))
            .field("week_start", .string, .required)
            .field("status", .string, .required)
            .field("request_json", .string, .required)
            .field("plan_json", .string)
            .field("error", .string)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .field("completed_at", .datetime)
            .create()

        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
        CREATE INDEX idx_weekly_plan_jobs_user_date ON weekly_plan_jobs(user_id, created_at DESC)
        """).run()

        // Partial unique index backstopping the controller's SELECT-then-
        // INSERT dedup check (WeeklyPlanController.create): two concurrent
        // POSTs for the same (user, weekStart) can both pass the SELECT
        // before either INSERTs. Without this, that race creates two rows,
        // dispatches two Claude Sonnet calls, and fires two pushes. Scoped
        // to queued/running only (not a plain unique-on-week) so a user can
        // still rebuild the same week again once the prior attempt finished
        // or failed.
        try await sql.raw("""
        CREATE UNIQUE INDEX idx_weekly_plan_jobs_user_week_inflight
            ON weekly_plan_jobs(user_id, week_start)
            WHERE status IN ('queued', 'running')
        """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("weekly_plan_jobs").delete()
    }
}
