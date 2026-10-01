@testable import App
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - Test mode (scripts/testenv.sh)

//
// Pure tests for the fixtures (each one must decode with the same decoder the
// real feature uses, so a fixture can't drift silently) and the gate (test
// routes never exist without TEMPO_TEST_MODE=1, never in production). The
// login round trip needs Postgres + Redis like the other controller tests.

@Suite("TestMode fixtures")
struct TestModeFixtureTests {
    private func reply(_ system: String, user: String = "hello", images: Int = 0) -> (name: String, text: String) {
        let ctx = TestFixtures.ClaudeContext(system: system, userText: user, imageCount: images, hasTools: false)
        let feature = TestFixtures.claudeFeature(for: ctx)
        return (feature.name, feature.reply(ctx))
    }

    private var snake: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    @Test func matchesFeaturesFromTheRawRequestBody() {
        // JSONEncoder escapes "/" — matching must parse the body, not grep it.
        let body = #"{"model":"claude-haiku-4-5","system":"You generate batch notification copy for a fitness\/accountability app.","messages":[{"role":"user","content":"go"}]}"#
        #expect(TestFixtures.claudeFeature(forRequestBody: body).name == "drill_batch")

        let tools = #"{"system":"<identity>\nName: A","tools":[{"name":"log_meal"}],"messages":[{"role":"user","content":[{"type":"text","text":"hi"}]}]}"#
        #expect(TestFixtures.claudeFeature(forRequestBody: tools).name == "coach_chat")

        let vision = #"{"system":"","messages":[{"role":"user","content":[{"type":"image","source":{}},{"type":"text","text":"Analyze this meal photo. Identify each food item."}]}]}"#
        let ctx = TestFixtures.context(fromRequestBody: vision)
        #expect(ctx.imageCount == 1)
        #expect(TestFixtures.claudeFeature(for: ctx).name == "photo_analysis")

        #expect(TestFixtures.claudeFeature(forRequestBody: #"{"system":"Something new"}"#).name == "unknown")
    }

    @Test func weeklyPlanUsesOnlyTargetedDayTypesAndRequestedMealCount() throws {
        let prompt = """
        <macro_targets_by_day_type>
        - Strength: 2800 kcal, 180g P, 320g C, 80g F
        - Rest: 2300 kcal, 170g P, 220g C, 75g F
        </macro_targets_by_day_type>
        - MEAL COUNT (user preference, OVERRIDES the default below): give EXACTLY 5 meals per day.
        """
        let text = TestFixtures.weeklyPlanJSON(prompt: prompt)
        let plan = try JSONDecoder().decode(AIWeeklyPlanResponse.self, from: Data(text.utf8))
        #expect(plan.days.count == 7)
        #expect(Set(plan.days.map(\.dayType)).isSubset(of: ["strength", "rest"]))
        #expect(plan.days.allSatisfy { $0.meals.count == 5 })
    }

    @Test func weeklyPlanSolvesThroughThePipeline() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        let req = Request(application: app, on: app.eventLoopGroup.next())
        struct Resolver: WeeklyPlanFoodResolving {
            func resolve(_ names: [String], on _: Request) async -> [String: ResolvedNutrition?] {
                var out: [String: ResolvedNutrition?] = [:]
                for (index, name) in names.enumerated() {
                    let f = TestFixtures.foods.first { $0.name == name }
                    out[name] = f.map { ResolvedNutrition(fdcId: index, description: $0.name, kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, fiber: nil, sugars: nil, confidence: 0.9) }
                }
                return out
            }
        }
        let prompt = "<macro_targets_by_day_type>\n- Strength: x\n</macro_targets_by_day_type>"
        let output = try await WeeklyPlanPipeline.build(
            rawAIText: TestFixtures.weeklyPlanJSON(prompt: prompt),
            targetsByDayType: ["strength": MacroTargets(kcal: 2800, proteinG: 180, carbsG: 320, fatG: 80)],
            resolver: Resolver(),
            on: req
        )
        #expect(output.days.count == 7)
    }

    @Test func recipeEchoesThePlannedFoods() throws {
        let user = "Meal: Lunch\nServings: 1\n- chicken breast: 180g (297 kcal, P56 C0 F6)\n- white rice: 220g (286 kcal, P6 C62 F1)"
        let (name, text) = reply("You are a culinary assistant for a nutrition app called Tempo. Given", user: user)
        #expect(name == "meal_recipe")
        let json = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let ingredients = try #require(json["ingredients"] as? [[String: Any]])
        #expect(ingredients.map { $0["name"] as? String } == ["chicken breast", "white rice"])
        #expect(ingredients.map { $0["quantityGrams"] as? Int } == [180, 220])
    }

    @Test func backendDecodedFixturesDecode() throws {
        let report = reply("You are an elite performance analyst inside the Tempo app.")
        _ = try snake.decode(WeeklyReportResponse.self, from: Data(report.text.utf8))

        let receipt = reply("You are a grocery RECEIPT extraction system. Convert")
        let payload = try snake.decode(HaikuReceiptPayload.self, from: Data(receipt.text.utf8))
        #expect(payload.lineItems.count == 6)

        let picks = reply("You are a supplements buying guide.")
        let decodedPicks = try snake.decode(SupplementPicksAIRawResponse.self, from: Data(picks.text.utf8))
        #expect(decodedPicks.picks.first?.approxPricePerServingUsd == 0.18)
        #expect(decodedPicks.toDTO(kind: "creatine").picks.first?.approxPricePerServingUSD == 0.18)

        let dashboard = reply("You generate dashboard insight cards for a student-athlete fitness app.")
        _ = try snake.decode(DashboardInsightsResponse.self, from: Data(dashboard.text.utf8))
    }

    @Test func everyJSONFixtureIsValidAndProseHasNoBraces() {
        // InsightService/Receipt slice from the first "{" — prose must not contain one.
        let ctx = TestFixtures.ClaudeContext(system: "", userText: "- oats: 80g (303 kcal, P10 C54 F5)", imageCount: 2, hasTools: false)
        for feature in TestFixtures.allFixtures {
            let text = feature.reply(ctx)
            if text.hasPrefix("{") || text.hasPrefix("[") {
                #expect((try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil, "\(feature.name) is not valid JSON")
                #expect((try? JSONSerialization.jsonObject(with: Data(feature.broken.utf8))) == nil, "\(feature.name) broken variant still parses")
            } else {
                #expect(!text.contains("{") && !text.contains("}"), "\(feature.name) prose contains a brace")
            }
        }
    }

    @Test func anthropicEnvelopeHasEveryFieldTheDecodersRequire() throws {
        let envelope = TestFixtures.anthropicMessage(text: "Line one\n\"quoted\"", model: "claude-haiku-4-5-20251001")
        let decoded = try snake.decode(ClaudeAPIRawResponse.self, from: Data(envelope.utf8))
        #expect(decoded.content.first?.text == "Line one\n\"quoted\"")
    }

    @Test func usdaFixtureMatchesByWord() throws {
        let body = TestFixtures.usdaSearch(query: "Chicken Breast grilled")
        let decoded = try JSONDecoder().decode(USDASearchRawResponse.self, from: Data(body.utf8))
        #expect(decoded.foods.contains { $0.description.hasPrefix("Chicken Breast") })
        let none = try JSONDecoder().decode(USDASearchRawResponse.self, from: Data(TestFixtures.usdaSearch(query: "zzzz").utf8))
        #expect(none.foods.isEmpty)
    }
}

// MARK: - extractJSON (crash fix)

@Suite("Claude JSON extraction")
struct ClaudeJSONExtractionTests {
    /// Before the fix both sliced `start ... end.upperBound`: a reply ending in
    /// "}" trapped (crashing the server) and a fenced one kept a stray "`".
    @Test(arguments: [
        #"Here is the plan: {"a":1}"#,
        "```json\n{\"a\":1}\n```",
        #"{"a":1}"#,
    ])
    func extractsExactlyTheObject(_ reply: String) {
        #expect(InsightService.extractJSON(from: reply) == #"{"a":1}"#)
        #expect(ReceiptStructuringService.extractJSON(from: reply) == #"{"a":1}"#)
    }
}

// MARK: - Gate + login

@Suite("TestMode routes", .serialized)
struct TestModeRouteTests {
    private func withApp(testMode: Bool, _ body: (Application) async throws -> Void) async throws {
        // Per app, not setenv: the env var would leak into suites running
        // in parallel.
        let app = try await Application.make(.testing)
        TestMode.force(testMode, on: app)
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

    private func login(_ app: Application, _ json: String, _ check: @escaping (XCTHTTPResponse) async throws -> Void) async throws {
        try await app.test(.POST, "v1/test/login", beforeRequest: { req in
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: "X-Device-Id", value: "sim-test")
            req.body = ByteBuffer(string: json)
        }, afterResponse: { res async throws in try await check(res) })
    }

    @Test func routesDoNotExistWithoutTheFlag() async throws {
        try await withApp(testMode: false) { app in
            #expect(app.testMode == nil)
            try await login(app, #"{"name":"nope"}"#) { res in
                #expect(res.status == .notFound)
            }
        }
    }

    @Test func hostedOrRemoteDatabaseNeverEnablesTestMode() {
        #expect(TestMode.runsLocally([:]))
        #expect(TestMode.runsLocally(["DB_HOST": "127.0.0.1"]))
        #expect(TestMode.runsLocally(["DATABASE_URL": "postgres://u:p@localhost:5432/x"]))
        #expect(!TestMode.runsLocally(["RAILWAY_ENVIRONMENT": "production"]))
        #expect(!TestMode.runsLocally(["DATABASE_URL": "postgres://u:p@db.railway.internal:5432/x"]))
        #expect(!TestMode.runsLocally(["DB_HOST": "10.0.0.5"]))
    }

    @Test func productionNeverEnablesTestMode() async throws {
        let app = try await Application.make(.production)
        TestMode.force(true, on: app)
        #expect(TestMode.isEnabled(app) == false)
        try await app.asyncShutdown()
    }

    @Test func loginCreatesAProUserThatPassesEveryGate() async throws {
        try await withApp(testMode: true) { app in
            let name = "t-\(UUID().uuidString.prefix(8).lowercased())"
            var token = ""
            var firstID = ""
            try await login(app, #"{"name":"\#(name)"}"#) { res in
                #expect(res.status == .ok)
                let body = try res.content.decode(TestModeController.LoginResponse.self)
                #expect(body.created)
                token = body.accessToken
                firstID = body.userId
            }
            // Pro-gated + consent-gated route.
            try await app.test(.GET, "v1/insights/weekly-report", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async in
                #expect(res.status == .ok)
            })
            // Same name → same account; fresh → a new one.
            try await login(app, #"{"name":"\#(name)"}"#) { res in
                let body = try res.content.decode(TestModeController.LoginResponse.self)
                #expect(!body.created)
                #expect(body.userId == firstID)
            }
            try await login(app, #"{"name":"\#(name)","fresh":true,"pro":false}"#) { res in
                let body = try res.content.decode(TestModeController.LoginResponse.self)
                #expect(body.created)
                #expect(body.userId != firstID)
                token = body.accessToken
            }
            try await app.test(.GET, "v1/insights/weekly-report", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
            }, afterResponse: { res async in
                #expect(res.status == .paymentRequired)
            })
        }
    }

    @Test func rejectsBadNames() async throws {
        try await withApp(testMode: true) { app in
            try await login(app, #"{"name":"Bad Name!"}"#) { res in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test func outboundCallsAreFakedOrBlocked() async throws {
        try await withApp(testMode: true) { app in
            let blocked = try await app.client.get("https://example.com/anything")
            #expect(blocked.status == .badGateway)
            app.testMode?.aiMode = .error
            let overloaded = try await app.client.post("https://api.anthropic.com/v1/messages") { req in
                try req.content.encode(["system": "x"])
            }
            #expect(overloaded.status.code == 529)
            #expect(app.testMode?.aiCalls.last?.status == 529)
        }
    }
}
