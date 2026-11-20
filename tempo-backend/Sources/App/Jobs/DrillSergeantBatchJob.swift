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
        _ = try await generate(app: context.application, now: context.application.now)
    }

    /// One pass for every Pro user with AI consent (or just `userID`).
    /// Returns how many batches were generated.
    @discardableResult
    func generate(app: Application, now: Date, userID onlyUserID: String? = nil) async throws -> Int {
        let db = app.db
        let logger = app.logger

        // Find every Pro user with AI consent. We bypass the per-request
        // SubscriptionMiddleware here because this is a background job, but
        // we still respect the same business logic.
        let activeSubs = try await UserSubscription.query(on: db)
            .filter(\.$isActive == true)
            .filter(\.$expirationDate > now)
            .all()

        var proUserIDs = Set(activeSubs.map { $0.$user.id })
        if let onlyUserID {
            proUserIDs = proUserIDs.intersection([onlyUserID])
        }
        guard !proUserIDs.isEmpty else {
            logger.info("[DrillSergeantBatchJob] no Pro users; skipping")
            return 0
        }

        let users = try await User.query(on: db)
            .filter(\.$id ~~ proUserIDs)
            .filter(\.$deletedAt == nil)
            .filter(\.$aiConsentAt != nil)
            .all()

        guard !users.isEmpty else {
            logger.info("[DrillSergeantBatchJob] no Pro users with AI consent; skipping")
            return 0
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
        let req = Request(application: app, on: app.eventLoopGroup.next())

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
        return ok
    }
}
