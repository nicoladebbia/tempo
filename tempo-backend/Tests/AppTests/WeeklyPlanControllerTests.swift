@testable import App
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
import XCTVapor

// MARK: - WeeklyPlanController tests

//
// Real Postgres + Redis harness (same pattern as
// FoodNutritionResolverCacheTests / TrainerProgramImportQuotaServiceTests).
// The `.mealPlans` queue worker never starts in the testing environment
// (see configure.swift), so dispatching the job here never actually runs
// it — these tests only exercise the controller's create/read/validate
// logic, never a live Claude call.

@Suite("WeeklyPlanController", .serialized)
struct WeeklyPlanControllerTests {
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

    // MARK: - Fixtures

    @discardableResult
    private func makeUser(app: Application, pro: Bool, tosAccepted: Bool = true, aiConsent: Bool = true) async throws -> (user: User, token: String) {
        let suffix = UUID().uuidString.prefix(12)
        let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: "Test User")
        if tosAccepted {
            user.tosAcceptedAt = Date()
        }
        if aiConsent {
            user.aiConsentAt = Date()
        }
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

        let req = Request(application: app, on: app.eventLoopGroup.next())
        let token = try await JWTService.issueAccessToken(userID: user.requireID(), deviceID: "test-device", on: req)
        return (user, token)
    }

    private func validTargets() -> [String: MacroTargetsDTO] {
        [
            "strength": MacroTargetsDTO(kcal: 2300, proteinG: 150, carbsG: 250, fatG: 70),
            "rest": MacroTargetsDTO(kcal: 2000, proteinG: 140, carbsG: 200, fatG: 65),
        ]
    }

    private func createBody(weekStart: String = "2026-09-28") -> ByteBuffer {
        let payload: [String: Any] = [
            "weekStart": weekStart,
            "system": "You are a meal planner.",
            "prompt": "Plan next week.",
            "targets": [
                "strength": ["kcal": 2300, "proteinG": 150, "carbsG": 250, "fatG": 70],
                "rest": ["kcal": 2000, "proteinG": 140, "carbsG": 200, "fatG": 65],
            ],
            "timezone": "America/New_York",
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return ByteBuffer(data: data)
    }

    // MARK: - Create

    @Test func createReturnsQueued() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app, pro: true)
            try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                req.body = createBody()
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawTestEnvelope<WeeklyPlanCreateWire>.self)
                #expect(json.ok == true)
                #expect(json.data.status == "queued")
                #expect(json.data.weekStart == "2026-09-28")
                #expect(UUID(uuidString: json.data.id) != nil)
            })
        }
    }

    @Test func duplicateForSameWeekReturnsSameID() async throws {
        try await withApp { app in
            let (user, token) = try await makeUser(app: app, pro: true)

            var firstID = ""
            try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                req.body = createBody()
            }, afterResponse: { res async throws in
                let json = try res.content.decode(RawTestEnvelope<WeeklyPlanCreateWire>.self)
                firstID = json.data.id
            })

            try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                req.body = createBody()
            }, afterResponse: { res async throws in
                let json = try res.content.decode(RawTestEnvelope<WeeklyPlanCreateWire>.self)
                #expect(json.data.id == firstID, "a second create for the same in-flight week must return the existing job")
                #expect(json.data.status == "queued")
            })

            // Scoped to this test's own user: the shared test database persists
            // rows across runs/suites, so an unscoped count would pick up
            // unrelated jobs for the same fixed weekStart from other tests.
            let count = try await WeeklyPlanJobRecord.query(on: app.db)
                .filter(\.$userID == user.requireID())
                .filter(\.$weekStart == "2026-09-28")
                .count()
            #expect(count == 1)
        }
    }

    /// The sequential `duplicateForSameWeekReturnsSameID` test above can't
    /// catch a race in the controller's SELECT-then-INSERT dedup check —
    /// two truly concurrent POSTs (double-tap, or a client retry after a
    /// timed-out-but-actually-succeeded request) can both pass the SELECT
    /// before either commits. This fires them concurrently via `async let`
    /// against the same real Postgres connection pool and asserts the
    /// partial unique index (CreateWeeklyPlanJobs) still lets only one
    /// in-flight job survive — the loser's insert must be caught and turned
    /// into "return the winner's job", never a 500 or a second row.
    @Test func concurrentCreatesForSameWeekProduceOnlyOneJob() async throws {
        try await withApp { app in
            let (user, token) = try await makeUser(app: app, pro: true)

            @Sendable func post() async throws -> String {
                var id = ""
                try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: token)
                    req.headers.contentType = .json
                    req.body = createBody(weekStart: "2028-03-06")
                }, afterResponse: { res async throws in
                    #expect(res.status == .ok, "neither racer should ever see a 500 from the unique-index collision")
                    let json = try res.content.decode(RawTestEnvelope<WeeklyPlanCreateWire>.self)
                    id = json.data.id
                })
                return id
            }

            async let first = post()
            async let second = post()
            let (idA, idB) = try await (first, second)
            #expect(idA == idB, "both racers must agree on a single winning job id")

            let count = try await WeeklyPlanJobRecord.query(on: app.db)
                .filter(\.$userID == user.requireID())
                .filter(\.$weekStart == "2028-03-06")
                .count()
            #expect(count == 1, "the partial unique index must prevent a second in-flight row")
        }
    }

    @Test func validationRejectsBadInput() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app, pro: true)

            try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                req.body = createBody(weekStart: "not-a-date")
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
            })

            try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                let payload: [String: Any] = [
                    "weekStart": "2026-10-05",
                    "system": "sys",
                    "prompt": "   ",
                    "targets": ["strength": ["kcal": 2300, "proteinG": 150, "carbsG": 250, "fatG": 70]],
                    "timezone": "America/New_York",
                ]
                req.body = ByteBuffer(data: try! JSONSerialization.data(withJSONObject: payload))
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest, "empty prompt must 400")
            })

            try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                let payload: [String: Any] = [
                    "weekStart": "2026-10-05",
                    "system": "sys",
                    "prompt": "plan it",
                    "targets": [String: Any](),
                    "timezone": "America/New_York",
                ]
                req.body = ByteBuffer(data: try! JSONSerialization.data(withJSONObject: payload))
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest, "empty targets must 400")
            })

            try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                let payload: [String: Any] = [
                    "weekStart": "2026-10-05",
                    "system": "sys",
                    "prompt": "plan it",
                    "targets": ["strength": ["kcal": 0, "proteinG": 150, "carbsG": 250, "fatG": 70]],
                    "timezone": "America/New_York",
                ]
                req.body = ByteBuffer(data: try! JSONSerialization.data(withJSONObject: payload))
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest, "a non-positive target must 400")
            })
        }
    }

    @Test func nonProUserIsBlocked() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app, pro: false)
            try await app.test(.POST, "v1/nutrition/weekly-plans", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                req.body = createBody(weekStart: "2026-11-02")
            }, afterResponse: { res async throws in
                #expect(res.status == .paymentRequired)
            })
        }
    }

    // MARK: - Latest / get

    @Test func latestReturnsOnlyCallersOwnJob() async throws {
        try await withApp { app in
            let (userA, tokenA) = try await makeUser(app: app, pro: true)
            let (userB, _) = try await makeUser(app: app, pro: true)

            let jobA = try WeeklyPlanJobRecord(userID: userA.requireID(), weekStart: "2026-12-07", requestJSON: "{}")
            try await jobA.save(on: app.db)
            let jobB = try WeeklyPlanJobRecord(userID: userB.requireID(), weekStart: "2026-12-07", requestJSON: "{}")
            try await jobB.save(on: app.db)

            try await app.test(.GET, "v1/nutrition/weekly-plans/latest", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: tokenA)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawTestEnvelope<WeeklyPlanStatusWire>.self)
                #expect(json.data.id == jobA.id?.uuidString)
            })
        }
    }

    @Test func latestReturnsNullDataWhenNoneExists() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app, pro: true)
            try await app.test(.GET, "v1/nutrition/weekly-plans/latest", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawTestEnvelope<WeeklyPlanStatusWire?>.self)
                #expect(json.data == nil)
            })
        }
    }

    @Test func staleRunningJobIsReportedAndPersistedAsFailed() async throws {
        try await withApp { app in
            let (user, token) = try await makeUser(app: app, pro: true)

            let job = try WeeklyPlanJobRecord(userID: user.requireID(), weekStart: "2027-01-04", status: .running, requestJSON: "{}")
            try await job.save(on: app.db)

            // Fluent's `@Timestamp(on: .create)` unconditionally stamps
            // created_at/updated_at to "now" during save() — setting the
            // property beforehand is silently overwritten. Backdate it with
            // a raw UPDATE afterwards so the row actually looks 20 minutes
            // old (> the job's 15-minute stale window) to the controller.
            let pastDate = Date().addingTimeInterval(-20 * 60)
            let sql = app.db as! SQLDatabase
            try await sql.raw("UPDATE weekly_plan_jobs SET created_at = \(bind: pastDate) WHERE id = \(bind: job.requireID())").run()

            try await app.test(.GET, "v1/nutrition/weekly-plans/latest", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawTestEnvelope<WeeklyPlanStatusWire>.self)
                #expect(json.data.status == "failed")
                #expect(json.data.error == "timed out")
            })

            let persisted = try await WeeklyPlanJobRecord.find(job.requireID(), on: app.db)
            #expect(persisted?.status == "failed")
        }
    }

    @Test func getByIDRejectsAnotherUsersJob() async throws {
        try await withApp { app in
            let (userA, _) = try await makeUser(app: app, pro: true)
            let (_, tokenB) = try await makeUser(app: app, pro: true)

            let jobA = try WeeklyPlanJobRecord(userID: userA.requireID(), weekStart: "2027-02-01", requestJSON: "{}")
            try await jobA.save(on: app.db)

            try await app.test(.GET, "v1/nutrition/weekly-plans/\(jobA.requireID())", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: tokenB)
            }, afterResponse: { res async throws in
                #expect(res.status == .notFound)
            })
        }
    }
}

// MARK: - Minimal decode-side wire types for these tests

// (the controller's own response DTOs are Encodable-only by design; tests
// decode against small mirror structs instead of adding Decodable there).

private struct RawTestEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
}

/// NOTE: no custom CodingKeys here — the response bytes are the literal
/// snake_case WeeklyPlanController emits ("week_start"), and `res.content
/// .decode` runs through the app's global `.convertFromSnakeCase` decoder,
/// which rewrites "week_start" -> "weekStart" BEFORE key matching. Adding an
/// explicit `case weekStart = "week_start"` here would make matching fail
/// (the container would look for a literal "week_start" key that no longer
/// exists post-conversion) — this is the same trap WeeklyPlanController's
/// own DTOs sidestep by using a bare `JSONEncoder()` with no strategy.
private struct WeeklyPlanCreateWire: Decodable {
    let id: String
    let status: String
    let weekStart: String
}

private struct WeeklyPlanStatusWire: Decodable, Equatable {
    let id: String
    let weekStart: String
    let status: String
    let error: String?
}
