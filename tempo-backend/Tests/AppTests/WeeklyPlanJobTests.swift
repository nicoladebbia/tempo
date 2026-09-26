@testable import App
import Fluent
import Foundation
import Queues
import Testing
import Vapor

// MARK: - WeeklyPlanJob tests

//
// Exercises the real `dequeue` end to end (status transitions, plan_json
// persisted, push attempted-but-safe) against real Postgres + Redis, with
// Claude stubbed via the injectable `WeeklyPlanAIClient` protocol —
// NutritionClaudeProxyService is an actor singleton with no seam of its own,
// so this protocol is what makes the job testable without a network call or
// a real Anthropic key. The job is invoked directly
// (`WeeklyPlanJob(...).dequeue(context, id)`), never through
// `req.queue.dispatch` — the `.mealPlans` worker never starts in the testing
// environment (configure.swift), so a dispatched job would just sit in
// Redis forever.

@Suite("WeeklyPlanJob", .serialized)
struct WeeklyPlanJobTests {
    private func withApp(_ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    private func makeUser(app: Application, pro: Bool) async throws -> User {
        let suffix = UUID().uuidString.prefix(12)
        let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: "Test User")
        user.tosAcceptedAt = Date()
        user.aiConsentAt = Date()
        try await user.save(on: app.db)
        if pro {
            let sub = try UserSubscription(
                userID: user.requireID(),
                productId: "tempo_pro_monthly",
                originalTransactionId: "orig_\(suffix)",
                purchaseDate: Date().addingTimeInterval(-86400),
                expirationDate: Date().addingTimeInterval(30 * 86400)
            )
            try await sub.save(on: app.db)
        }
        return user
    }

    private func makeJobRecord(app: Application, userID: String, targets: [String: MacroTargetsDTO]) async throws -> WeeklyPlanJobRecord {
        let payload = WeeklyPlanRequestPayload(
            system: "You are a meal planner.",
            prompt: "Plan next week.",
            targets: targets,
            timezone: "America/New_York"
        )
        let requestJSON = try String(data: JSONEncoder().encode(payload), encoding: .utf8)!
        let job = WeeklyPlanJobRecord(userID: userID, weekStart: "2026-09-28", requestJSON: requestJSON)
        try await job.save(on: app.db)
        return job
    }

    private func defaultTargets() -> [String: MacroTargetsDTO] {
        ["strength": MacroTargetsDTO(kcal: 2300, proteinG: 150, carbsG: 250, fatG: 70)]
    }

    private final class FakeAIClient: WeeklyPlanAIClient, @unchecked Sendable {
        private var responses: [Result<String, Error>]
        private(set) var callCount = 0

        init(responses: [Result<String, Error>]) {
            self.responses = responses
        }

        func generate(system _: String, prompt _: String, on _: Request) async throws -> String {
            defer { callCount += 1 }
            let index = min(callCount, responses.count - 1)
            switch responses[index] {
            case let .success(text): return text
            case let .failure(error): throw error
            }
        }
    }

    private struct EmptyResolver: WeeklyPlanFoodResolving {
        func resolve(_: [String], on _: Request) async -> [String: ResolvedNutrition?] {
            [:]
        }
    }

    private static let validPlanJSON = """
    {"days":[{"dayIndex":0,"dayType":"strength","meals":[{"mealNumber":1,"mealName":"Breakfast","scheduledTime":"07:30",
      "foods":[{"name":"oats","quantityGrams":80,"calories":300,"proteinG":10,"carbsG":54,"fatG":5,"source":"home"}]}],
      "supplements":[]}]}
    """

    // MARK: - Success

    @Test func successfulJobStoresPlanAndMarksReady() async throws {
        try await withApp { app in
            let user = try await makeUser(app: app, pro: true)
            let job = try await makeJobRecord(app: app, userID: user.requireID(), targets: defaultTargets())

            let aiClient = FakeAIClient(responses: [.success(Self.validPlanJSON)])
            let weeklyJob = WeeklyPlanJob(aiClient: aiClient, makeResolver: { EmptyResolver() })
            let context = app.queues.queue(.mealPlans).context

            try await weeklyJob.dequeue(context, job.requireID())

            let persisted = try #require(try await WeeklyPlanJobRecord.find(job.requireID(), on: app.db))
            #expect(persisted.status == "ready")
            #expect(persisted.error == nil)
            #expect(persisted.completedAt != nil)
            let planData = try #require(persisted.planJSON?.data(using: .utf8))
            let output = try JSONDecoder().decode(WeeklyPlanOutput.self, from: planData)
            #expect(output.days.count == 1)
            #expect(output.days[0].meals[0].foods[0].source == "ai")
            #expect(aiClient.callCount == 1)
        }
    }

    // MARK: - Subscription required

    @Test func nonProUserFailsWithSubscriptionRequired() async throws {
        try await withApp { app in
            let user = try await makeUser(app: app, pro: false)
            let job = try await makeJobRecord(app: app, userID: user.requireID(), targets: defaultTargets())

            let aiClient = FakeAIClient(responses: [.success(Self.validPlanJSON)])
            let weeklyJob = WeeklyPlanJob(aiClient: aiClient, makeResolver: { EmptyResolver() })
            let context = app.queues.queue(.mealPlans).context

            try await weeklyJob.dequeue(context, job.requireID())

            let persisted = try #require(try await WeeklyPlanJobRecord.find(job.requireID(), on: app.db))
            #expect(persisted.status == "failed")
            #expect(persisted.error == "subscription_required")
            #expect(aiClient.callCount == 0, "must never call Claude for a non-entitled user")
        }
    }

    // MARK: - Unreadable AI response (with retry)

    @Test func unreadableResponseRetriesOnceThenFails() async throws {
        try await withApp { app in
            let user = try await makeUser(app: app, pro: true)
            let job = try await makeJobRecord(app: app, userID: user.requireID(), targets: defaultTargets())

            let aiClient = FakeAIClient(responses: [.success("not json at all"), .success("still not json")])
            let weeklyJob = WeeklyPlanJob(aiClient: aiClient, makeResolver: { EmptyResolver() })
            let context = app.queues.queue(.mealPlans).context

            try await weeklyJob.dequeue(context, job.requireID())

            let persisted = try #require(try await WeeklyPlanJobRecord.find(job.requireID(), on: app.db))
            #expect(persisted.status == "failed")
            #expect(persisted.error == "ai_unreadable")
            #expect(aiClient.callCount == 2, "a parse failure must retry exactly once")
        }
    }

    @Test func parseFailureThenSuccessOnRetrySucceeds() async throws {
        try await withApp { app in
            let user = try await makeUser(app: app, pro: true)
            let job = try await makeJobRecord(app: app, userID: user.requireID(), targets: defaultTargets())

            let aiClient = FakeAIClient(responses: [.success("garbage"), .success(Self.validPlanJSON)])
            let weeklyJob = WeeklyPlanJob(aiClient: aiClient, makeResolver: { EmptyResolver() })
            let context = app.queues.queue(.mealPlans).context

            try await weeklyJob.dequeue(context, job.requireID())

            let persisted = try #require(try await WeeklyPlanJobRecord.find(job.requireID(), on: app.db))
            #expect(persisted.status == "ready")
            #expect(aiClient.callCount == 2)
        }
    }

    // MARK: - Budget exhausted (no retry)

    @Test func budgetExhaustedFailsWithoutRetry() async throws {
        try await withApp { app in
            let user = try await makeUser(app: app, pro: true)
            let job = try await makeJobRecord(app: app, userID: user.requireID(), targets: defaultTargets())

            let aiClient = FakeAIClient(responses: [.failure(NutritionProxyError.budgetExhausted)])
            let weeklyJob = WeeklyPlanJob(aiClient: aiClient, makeResolver: { EmptyResolver() })
            let context = app.queues.queue(.mealPlans).context

            try await weeklyJob.dequeue(context, job.requireID())

            let persisted = try #require(try await WeeklyPlanJobRecord.find(job.requireID(), on: app.db))
            #expect(persisted.status == "failed")
            #expect(persisted.error == "ai_budget_exhausted")
            #expect(aiClient.callCount == 1, "a non-parse error (budget) must not be retried")
        }
    }

    @Test func missingJobRecordIsANoOp() async throws {
        try await withApp { app in
            let aiClient = FakeAIClient(responses: [.success(Self.validPlanJSON)])
            let weeklyJob = WeeklyPlanJob(aiClient: aiClient, makeResolver: { EmptyResolver() })
            let context = app.queues.queue(.mealPlans).context

            // Should log + return, never throw.
            try await weeklyJob.dequeue(context, UUID())
            #expect(aiClient.callCount == 0)
        }
    }
}
