import Fluent
import Foundation
import Queues
import Vapor

// MARK: - WeeklyPlanJob

//
// Background half of "build next week": WeeklyPlanController creates a
// WeeklyPlanJobRecord (status=queued) and dispatches this job with the
// record's id as payload. Runs on the dedicated `.mealPlans` queue — NOT
// `.default` — because production currently starts no in-process worker at
// all (Dockerfile/railway.toml only run `serve`), and configure.swift only
// starts a worker for `.mealPlans` specifically, so this feature can't
// accidentally wake up other jobs (DrillSergeantBatchJob, WhoopWebhookJob,
// scheduled jobs) that nobody has verified are safe to run yet.

extension QueueName {
    static let mealPlans = QueueName(string: "meal-plans")
}

struct WeeklyPlanJob: AsyncJob {
    typealias Payload = UUID

    let aiClient: any WeeklyPlanAIClient
    let makeResolver: @Sendable () -> any WeeklyPlanFoodResolving

    init(
        aiClient: any WeeklyPlanAIClient = LiveWeeklyPlanAIClient(),
        makeResolver: @escaping @Sendable () -> any WeeklyPlanFoodResolving = { FoodNutritionResolver() }
    ) {
        self.aiClient = aiClient
        self.makeResolver = makeResolver
    }

    func dequeue(_ context: QueueContext, _ payload: UUID) async throws {
        let req = Request(application: context.application, on: context.eventLoop)

        guard let job = try await WeeklyPlanJobRecord.find(payload, on: req.db) else {
            context.logger.warning("[WeeklyPlanJob] job \(payload) not found — skipping")
            return
        }

        do {
            try await run(job: job, req: req)
        } catch {
            context.logger.error("[WeeklyPlanJob] job \(payload) failed: \(error)")
            job.statusEnum = .failed
            job.error = Self.errorCode(for: error)
            job.completedAt = Date()
            try? await job.save(on: req.db)
        }
    }

    // MARK: - Steps a-g

    private func run(job: WeeklyPlanJobRecord, req: Request) async throws {
        // a. status=running, Pro check.
        job.statusEnum = .running
        try await job.save(on: req.db)

        guard try await ProEntitlement.isEntitled(userID: job.userID, on: req) else {
            throw WeeklyPlanJobError.subscriptionRequired
        }

        guard
            let requestData = job.requestJSON.data(using: .utf8),
            let stored = try? JSONDecoder().decode(WeeklyPlanRequestPayload.self, from: requestData)
        else {
            throw WeeklyPlanJobError.aiFailed("stored request payload is corrupt")
        }

        // b + c. Call Claude, parse/resolve/solve/rewrite (one retry on
        // parse failure only — a budget/network error propagates immediately).
        let resolver = makeResolver()
        let targets = stored.targets.mapValues(\.asMacroTargets)
        let output = try await generateAndParse(system: stored.system, prompt: stored.prompt, targets: targets, resolver: resolver, req: req)

        // f. Store + mark ready.
        let encoder = JSONEncoder()
        let planData = try encoder.encode(output)
        job.planJSON = String(data: planData, encoding: .utf8)
        job.statusEnum = .ready
        job.completedAt = Date()
        try await job.save(on: req.db)

        // g. Push — must never fail the job.
        do {
            try await APNsService.sendAlert(
                to: job.userID,
                title: "Your week is planned",
                body: "7 days of meals, macros checked. Tap to review.",
                type: .mealPlanReady,
                data: ["type": "meal_plan_ready", "jobId": job.id?.uuidString ?? ""],
                on: req
            )
        } catch {
            req.logger.warning("[WeeklyPlanJob] push failed for job \(job.id?.uuidString ?? "?"): \(error)")
        }
    }

    private func generateAndParse(
        system: String,
        prompt: String,
        targets: [String: MacroTargets],
        resolver: any WeeklyPlanFoodResolving,
        req: Request
    ) async throws -> WeeklyPlanOutput {
        var lastParseError: Error = WeeklyPlanPipelineError.unreadable("no attempts ran")
        for attempt in 0 ..< 2 {
            let text = try await aiClient.generate(system: system, prompt: prompt, on: req)
            do {
                return try await WeeklyPlanPipeline.build(
                    rawAIText: text,
                    targetsByDayType: targets,
                    resolver: resolver,
                    on: req
                )
            } catch {
                lastParseError = error
                req.logger.warning("[WeeklyPlanJob] parse attempt \(attempt) failed: \(error)")
            }
        }
        throw lastParseError
    }

    // MARK: - Error mapping

    static func errorCode(for error: Error) -> String {
        if let jobError = error as? WeeklyPlanJobError {
            return jobError.code
        }
        if error is WeeklyPlanPipelineError {
            return "ai_unreadable"
        }
        if let proxyError = error as? NutritionProxyError {
            if case .budgetExhausted = proxyError {
                return "ai_budget_exhausted"
            }
            // Any other NutritionProxyError (bad model, malformed response,
            // Anthropic API error) is still genuinely an AI-call failure.
            return "ai_failed"
        }
        // Anything else (Postgres/Redis/Fluent save failure, decoding bug,
        // etc.) is infra, not the AI — labeling it "ai_failed" would send
        // support/telemetry chasing a Claude problem that doesn't exist.
        return "internal_error"
    }
}

// MARK: - Job errors

enum WeeklyPlanJobError: Error, Sendable {
    case subscriptionRequired
    case aiFailed(String)

    var code: String {
        switch self {
        case .subscriptionRequired: "subscription_required"
        case .aiFailed: "ai_failed"
        }
    }
}

// MARK: - Stored request payload (request_json column)

struct WeeklyPlanRequestPayload: Codable, Sendable {
    let system: String
    let prompt: String
    let targets: [String: MacroTargetsDTO]
    let timezone: String
}

/// Wire/storage-friendly `MacroTargets` — `MacroTargets` itself (in
/// MacroSolver.swift) intentionally has no Codable conformance since it's a
/// pure-math type from the macro-engine PR; this is the one place that
/// needs to move it in and out of JSON.
struct MacroTargetsDTO: Content, Sendable {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    var asMacroTargets: MacroTargets {
        MacroTargets(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
    }
}
