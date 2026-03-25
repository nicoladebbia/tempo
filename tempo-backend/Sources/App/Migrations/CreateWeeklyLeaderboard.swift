import Fluent
import SQLKit

// MARK: - Create Weekly Leaderboard Materialized View
// Per MODULE_ARENA.md — Leaderboard refreshed periodically.
// Per BACKEND_API.md Section 10.5 — Leaderboard endpoints.

struct CreateWeeklyLeaderboard: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        // Create materialized view for weekly leaderboard
        // Aggregates XP events from the current ISO week.
        try await sql.raw("""
            CREATE MATERIALIZED VIEW IF NOT EXISTS weekly_leaderboard AS
            SELECT
                u.id AS user_id,
                u.username,
                u.display_name,
                u.level,
                u.streak_days,
                COALESCE(SUM(xe.base_xp), 0) AS weekly_raw_xp,
                COALESCE(SUM(xe.multiplied_xp), 0) AS weekly_total_xp,
                RANK() OVER (ORDER BY COALESCE(SUM(xe.base_xp), 0) DESC) AS rank
            FROM users u
            LEFT JOIN xp_events xe ON xe.user_id = u.id
                AND xe.created_at >= date_trunc('week', CURRENT_DATE)
            WHERE u.deleted_at IS NULL
            GROUP BY u.id, u.username, u.display_name, u.level, u.streak_days
            ORDER BY weekly_raw_xp DESC
            """).run()

        // Create unique index for concurrent refresh
        try await sql.raw("""
            CREATE UNIQUE INDEX idx_weekly_leaderboard_user ON weekly_leaderboard(user_id)
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("DROP MATERIALIZED VIEW IF EXISTS weekly_leaderboard").run()
    }
}
