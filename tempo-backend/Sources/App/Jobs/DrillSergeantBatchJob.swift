import Fluent
import Foundation
import Queues
import Vapor

// MARK: - Drill Sergeant Batch Job
//
// Per AI_INTELLIGENCE_ENGINE.md §3.4 + INTELLIGENCE_REMEDIATION_PLAN.md §7.4.
//
// Runs Sun 20:00 (covers Mon-Wed) and Wed 20:00 (covers Thu-Sat). For each
// Pro user with AI consent, generates a 3-day batch of notification copy and
// stashes it in Redis via DrillSergeantBatchService. The notification
// scheduler reads from the cache when it fires pushes, eliminating live
// Claude calls in the push hot path.

struct DrillSergeantBatchJob: AsyncScheduledJob {
    var name: String { "DrillSergeantBatchJob" }

    func run(context: QueueContext) async throws {
        let db = context.application.db
        let logger = context.application.logger

        // Find every Pro user with AI consent. We bypass the per-request
        // SubscriptionMiddleware here because this is a background job, but
        // we still respect the same business logic.
        let now = Date()
        let activeSubs = try await UserSubscription.query(on: db)
            .filter(\.$isActive == true)
            .filter(\.$expirationDate > now)
            .all()

        let proUserIDs = Set(activeSubs.map { $0.$user.id })
        guard !proUserIDs.isEmpty else {
            logger.info("[DrillSergeantBatchJob] no Pro users; skipping")
            return
        }

        let users = try await User.query(on: db)
            .filter(\.$id ~~ proUserIDs)
            .filter(\.$deletedAt == nil)
            .filter(\.$aiConsentAt != nil)
            .all()

        guard !users.isEmpty else {
            logger.info("[DrillSergeantBatchJob] no Pro users with AI consent; skipping")
            return
        }

        // Batch start = tomorrow (UTC). The scheduler runs Sun 20:00 / Wed 20:00,
        // so we generate for the upcoming Mon-Wed or Thu-Sat block.
        let calendar = Calendar(identifier: .gregorian)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let batchStart = formatter.string(from: tomorrow)

        // Build a synthetic Request for AI services that expect one.
        let req = Request(application: context.application, on: context.eventLoop)

        var ok = 0
        var failed = 0
        for user in users {
            guard let userId = user.id else { continue }
            let input = DrillSergeantBatchInput(
                userId: userId,
                batchStart: batchStart,
                userFirstName: user.displayName.split(separator: " ").first.map(String.init),
                recoveryTrend7day: [],   // populated by future signal-aggregation hooks
                upcomingEvents: [],
                recentStreakDays: user.streakDays
            )
            do {
                _ = try await DrillSergeantBatchService.shared.generate(input: input, on: req)
                ok += 1
            } catch {
                logger.warning("[DrillSergeantBatchJob] user=\(userId) failed: \(error.localizedDescription)")
                failed += 1
            }
        }

        logger.info("[DrillSergeantBatchJob] batch_start=\(batchStart) ok=\(ok) failed=\(failed)")
    }
}
