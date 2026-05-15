import Vapor
import Queues
import Fluent

// MARK: - Processed Notifications Cleanup Job
//
// Per LAUNCH_PUNCH_LIST.md §3.2 follow-up.
//
// The processed_appstore_notifications table grows monotonically — every
// distinct notification UUID Apple delivers becomes a row, and the table
// only exists to support idempotency on retries. Apple retries within a
// few hours window at most, so anything older than a day is safe to drop.
// We keep 90 days as a comfort margin (a paranoid Apple bug couldn't
// trigger a stale-retry collision).
//
// Runs daily at 04:00 UTC — quiet hour in both US and EU, well clear of
// peak-usage windows.

struct ProcessedNotificationsCleanupJob: AsyncScheduledJob {

    /// Rows older than this are deleted on each run.
    static let retentionDays: Int = 90

    func run(context: QueueContext) async throws {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86_400)

        // .delete() returns Void; we don't get a row count back from
        // Fluent's bulk delete. Log the cutoff timestamp so audit-trail
        // reads make sense if we ever need to investigate.
        try await ProcessedAppStoreNotification.query(on: context.application.db)
            .filter(\.$receivedAt < cutoff)
            .delete()
        context.logger.info(
            "[appstore_cleanup] purged processed_appstore_notifications older than \(cutoff)"
        )
    }
}
