import Vapor
import Queues
import SQLKit

// MARK: - Leaderboard Refresh Job
// Per BACKEND_API.md Section 26.1 — Refreshes materialized view every 5 minutes.
// Per BUILD_PLAN step 14.2 — Scheduled job for weekly leaderboard materialized view.

struct LeaderboardRefreshJob: AsyncScheduledJob {

    func run(context: QueueContext) async throws {
        try await refresh(app: context.application)
    }

    func refresh(app: Application) async throws {
        app.logger.info("Refreshing weekly leaderboard materialized view...")

        guard let sql = app.db as? SQLDatabase else {
            app.logger.warning("SQL database not available for leaderboard refresh.")
            return
        }

        // CONCURRENTLY allows reads during refresh (requires unique index)
        try await sql.raw("REFRESH MATERIALIZED VIEW CONCURRENTLY weekly_leaderboard").run()

        app.logger.info("Weekly leaderboard refreshed successfully.")
    }
}
