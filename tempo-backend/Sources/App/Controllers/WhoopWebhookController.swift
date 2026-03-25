import Vapor
import Fluent
import Queues
@preconcurrency import Redis

// MARK: - Whoop Webhook Controller
// Per INTEGRATION_SPECS.md Section 1.4 — Receives and processes Whoop webhooks.
// POST /v1/webhooks/whoop — Verify HMAC, check idempotency, enqueue background job.

struct WhoopWebhookController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post(use: handleWebhook)
    }

    // MARK: - POST /
    // Per INTEGRATION_SPECS.md Section 1.4 — Webhook handler.
    // HMAC verification is handled by WhoopWebhookMiddleware (applied at route level).

    func handleWebhook(_ req: Request) async throws -> HTTPStatus {
        // 1. Parse the event
        let event = try req.content.decode(WhoopWebhookEvent.self)

        req.logger.info("Whoop webhook received: type=\(event.type), trace_id=\(event.traceId)")

        // 2. Idempotency check using trace_id (24-hour dedup window)
        let cacheKey = RedisKey("whoop_webhook:\(event.traceId)")
        if let _ = try await req.redis.get(cacheKey, as: String.self).get() {
            req.logger.info("Duplicate webhook \(event.traceId), skipping")
            return .ok
        }
        // Mark as processing (TTL: 24 hours)
        _ = try await req.redis.setex(cacheKey, to: "processing", expirationInSeconds: 86400).get()

        // 3. Look up Tempo user by Whoop user ID
        guard let integration = try await WhoopIntegration.query(on: req.db)
            .filter(\.$whoopUserID == String(event.userId))
            .first() else {
            req.logger.warning("Unknown Whoop user ID: \(event.userId)")
            // Return 200 anyway to prevent Whoop from retrying endlessly
            return .ok
        }

        let tempoUserID = integration.$user.id

        // 4. Enqueue background processing job
        try await req.queue.dispatch(WhoopWebhookJob.self, WhoopWebhookJob.Payload(
            userId: tempoUserID,
            eventType: event.type,
            resourceId: event.id,
            traceId: event.traceId
        ))

        // 5. Return 200 immediately — processing is async
        return .ok
    }
}

// MARK: - Webhook Event DTO

struct WhoopWebhookEvent: Content {
    let type: String
    let id: Int64
    let userId: Int
    let traceId: String

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case userId = "user_id"
        case traceId = "trace_id"
    }
}

// MARK: - Webhook Background Job
// Per INTEGRATION_SPECS.md Section 1.4 — Async webhook processing.

struct WhoopWebhookJob: AsyncJob {
    struct Payload: Codable {
        let userId: String
        let eventType: String
        let resourceId: Int64
        let traceId: String
    }

    func dequeue(_ context: QueueContext, _ payload: Payload) async throws {
        let db = context.application.db

        switch payload.eventType {
        case "recovery.updated":
            try await invalidateCache(
                pattern: "whoop:\(payload.userId):recovery:*",
                on: context.application
            )
            context.logger.info("Recovery updated for user \(payload.userId)")

        case "sleep.updated":
            try await invalidateCache(
                pattern: "whoop:\(payload.userId):sleep:*",
                on: context.application
            )
            context.logger.info("Sleep updated for user \(payload.userId)")

        case "workout.updated":
            try await invalidateCache(
                pattern: "whoop:\(payload.userId):workouts:*",
                on: context.application
            )
            context.logger.info("Workout updated for user \(payload.userId)")

        case "cycle.updated":
            try await invalidateCache(
                pattern: "whoop:\(payload.userId):cycles:*",
                on: context.application
            )
            context.logger.info("Cycle updated for user \(payload.userId)")

        default:
            context.logger.warning("Unhandled Whoop webhook type: \(payload.eventType)")
        }

        // Update last sync timestamp on the integration
        if let integration = try await WhoopIntegration.query(on: db)
            .filter(\.$user.$id == payload.userId)
            .first() {
            integration.lastSyncAt = Date()
            integration.lastSyncStatus = "webhook_\(payload.eventType)"
            try await integration.save(on: db)
        }

        // Mark webhook as fully processed
        let cacheKey = RedisKey("whoop_webhook:\(payload.traceId)")
        _ = try await context.application.redis.setex(
            cacheKey, to: "completed", expirationInSeconds: 86400
        ).get()
    }

    func error(_ context: QueueContext, _ error: Error, _ payload: Payload) async throws {
        context.logger.error("Whoop webhook processing failed: \(error) for trace_id: \(payload.traceId)")
        let cacheKey = RedisKey("whoop_webhook:\(payload.traceId)")
        _ = try await context.application.redis.setex(
            cacheKey, to: "failed", expirationInSeconds: 86400
        ).get()
    }

    /// Invalidate cached Whoop data by scanning for matching keys.
    private func invalidateCache(pattern: String, on app: Application) async throws {
        var cursor: Int = 0
        repeat {
            let (nextCursor, keys) = try await app.redis.scan(
                startingFrom: cursor,
                matching: pattern,
                count: 100
            ).get()
            cursor = nextCursor

            for key in keys {
                _ = try await app.redis.delete(RedisKey(key)).get()
            }
        } while cursor != 0
    }
}
