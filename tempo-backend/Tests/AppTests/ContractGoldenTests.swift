@testable import App
import Fluent
import Foundation
import Queues
import Redis
import Testing
import Vapor
import XCTVapor

// MARK: - App <-> server contract goldens

//
// For every route the iOS app calls, this writes the JSON the server REALLY
// sends to `contracts/golden/<slug>.json` (repo root). The iOS test
// `APIContractTests` decodes each file with the app's real DTOs, so a key the
// server renamed (or the app spells differently) fails a test instead of
// failing silently on a phone.
//
//   swift test --filter ContractGolden                          -> FAILS if a golden differs
//   TEMPO_UPDATE_CONTRACTS=1 swift test --filter ContractGolden -> rewrites the goldens
//
// How each golden is produced:
//   "driven"  : the real route, in-process (`app.test`) in test mode, as a Pro,
//               consented test user. Outside services are the test-mode fakes.
//   "encoded" : the route needs a real ANTHROPIC_API_KEY/OPENAI key (an env var
//               other suites assert is UNSET, so it can't be set here without
//               racing them) or an Apple identity token. The server's own
//               response type is encoded through the same path the route uses
//               (`Envelope` -> global snake_case ContentConfiguration) from a
//               value with EVERY optional filled in, since Swift omits nil keys.
//
// Volatile values (ids, timestamps, tokens, request ids) are normalized so a
// golden only changes when the SHAPE does. See contracts/README.md.

@Suite("ContractGolden", .serialized)
struct ContractGoldenTests {
    // MARK: - Harness

    private struct Session {
        let accessToken: String
        let refreshToken: String
        let userID: String
    }

    private func withApp(_ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        TestMode.force(true, on: app)
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

    private static let deviceID = "contract-device"

    private func login(_ app: Application, name: String, pro: Bool = true) async throws -> Session {
        var session: Session?
        try await app.test(.POST, "v1/test/login", beforeRequest: { req in
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: "X-Device-Id", value: Self.deviceID)
            req.body = ByteBuffer(string: #"{"name":"\#(name)","fresh":true,"pro":\#(pro)}"#)
        }, afterResponse: { res async throws in
            #expect(res.status == .ok)
            let body = try res.content.decode(TestModeController.LoginResponse.self)
            session = Session(accessToken: body.accessToken, refreshToken: body.refreshToken, userID: body.userId)
        })
        return try #require(session)
    }

    /// Runs a request in-process and returns the raw response body.
    @discardableResult
    private func call(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        token: String?,
        body: String? = nil,
        expect status: HTTPStatus = .ok,
        file _: StaticString = #filePath,
        line _: UInt = #line
    ) async throws -> Data {
        var data = Data()
        try await app.test(method, path, beforeRequest: { req in
            if let token {
                req.headers.bearerAuthorization = .init(token: token)
            }
            req.headers.replaceOrAdd(name: "X-Device-Id", value: Self.deviceID)
            if let body {
                req.headers.contentType = .json
                req.body = ByteBuffer(string: body)
            }
        }, afterResponse: { res async throws in
            data = Data(res.body.readableBytesView)
            #expect(res.status == status, "\(method) \(path) -> \(res.status): \(String(decoding: data, as: UTF8.self).prefix(300))")
        })
        return data
    }

    /// What the route would send for `value`: `Envelope` through Vapor's real
    /// content encoder (global snake_case + iso8601 from configure.swift).
    private func envelopeJSON(_ app: Application, _ value: some Content) async throws -> Data {
        let req = Request(application: app, on: app.eventLoopGroup.next())
        let response = try await Envelope(data: value, requestID: "req_000000000000000000000000").encodeResponse(for: req)
        return Data(response.body.buffer?.readableBytesView ?? [])
    }

    private func rawJSON(_ app: Application, _ value: some Content) async throws -> Data {
        let req = Request(application: app, on: app.eventLoopGroup.next())
        let response = try await value.encodeResponse(for: req)
        return Data(response.body.buffer?.readableBytesView ?? [])
    }

    // MARK: - Golden files

    private static var goldenDir: URL {
        // Tests/AppTests/ContractGoldenTests.swift -> tempo-backend -> repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("contracts/golden", isDirectory: true)
    }

    private static var updating: Bool {
        ProcessInfo.processInfo.environment["TEMPO_UPDATE_CONTRACTS"] == "1"
    }

    private func golden(_ slug: String, _ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let canonical = try ContractNormalizer.canonicalJSON(from: data)
        let url = Self.goldenDir.appendingPathComponent("\(slug).json")
        if Self.updating {
            try FileManager.default.createDirectory(at: Self.goldenDir, withIntermediateDirectories: true)
            try canonical.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
            Issue.record(
                "No golden for \(slug). Run: TEMPO_UPDATE_CONTRACTS=1 swift test --filter ContractGolden, then commit contracts/golden/\(slug).json",
                sourceLocation: sourceLocation
            )
            return
        }
        #expect(
            existing == canonical,
            """
            \(slug).json differs from what the server now sends. If the change is intended, regenerate with
            TEMPO_UPDATE_CONTRACTS=1 swift test --filter ContractGolden, commit the diff, and make the iOS
            APIContractTests pass (update the app DTO or fix the server).
            --- server now sends ---
            \(canonical)
            """,
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Auth + user (driven)

    @Test func authAndUserRoutes() async throws {
        try await withApp { app in
            let session = try await login(app, name: "contract-user")

            // /auth/apple needs a real Apple identity token: encode the same type /auth/refresh returns.
            try golden("auth-apple", await rawJSON(app, AuthTokenResponse(accessToken: "eyJhbGciOiJIUzI1NiJ9.e30.c2ln", refreshToken: "rt_00000000000000000000000000000000")))

            // Refresh: no bearer, same device id as the login. Auth routes allow 10/min per IP
            // and every `swift test` run (and other suites) shares that counter, so reset it.
            let keys = try await app.redis.send(command: "KEYS", with: [RESPValue(from: "ratelimit:*auth/refresh*")]).get().array ?? []
            for key in keys {
                _ = try await app.redis.delete(RedisKey(key.string ?? "")).get()
            }
            let refreshed = try await call(app, .POST, "v1/auth/refresh", token: nil, body: #"{"refresh_token":"\#(session.refreshToken)"}"#)
            try golden("auth-refresh", refreshed)

            try golden("user-me-get", await call(app, .GET, "v1/user/me", token: session.accessToken))
            try golden("user-ai-consent", await call(app, .POST, "v1/user/ai-consent", token: session.accessToken, body: #"{"consented":true}"#))
            try golden("user-accept-tos", await call(app, .POST, "v1/user/accept-tos", token: session.accessToken, body: #"{"document_version":"2026-09"}"#))
            try golden("user-daily-plan-profile-put", await call(app, .PUT, "v1/user/daily-plan-profile", token: session.accessToken, body: Self.dailyPlanProfileBody))
        }
    }

    private static let dailyPlanProfileBody = """
    {"wake_time_minutes":420,"sleep_target_hours":8.0,"chronotype":"neutral","training_time_preference":"evening",
     "eating_window_preset":"standard","eating_window_start_minutes":480,"eating_window_end_minutes":1200,
     "breakfast_skipped":false,"post_workout_mandatory":true,"study_session_length_minutes":50,
     "weekend_differential":"relaxed","term_start_date":"2026-09-01T00:00:00Z","term_end_date":"2026-12-15T00:00:00Z",
     "class_blocks":[{"weekday":1,"start_minute_of_day":540,"end_minute_of_day":630,"course_code":"CS101","course_name":"Intro","location":"Hall A"}],
     "work_blocks":[{"weekday":3,"start_minute_of_day":840,"end_minute_of_day":1020,"label":"Shift"}]}
    """

    @Test func accountDeletionRoute() async throws {
        try await withApp { app in
            let session = try await login(app, name: "contract-delete")
            try golden("user-me-delete", await call(app, .DELETE, "v1/user/me", token: session.accessToken))
        }
    }

    // MARK: - Devices (driven)

    @Test func deviceRoutes() async throws {
        try await withApp { app in
            let session = try await login(app, name: "contract-device")
            let token = String(repeating: "ab12", count: 16)
            let body = #"{"token":"\#(token)","device_id":"dev-1","device_name":"iPhone","app_version":"1.0","bundle_id":"app.tempo.Tempo","apns_environment":"sandbox"}"#
            try golden("devices-register", await call(app, .POST, "v1/devices/register", token: session.accessToken, body: body))
            try golden("devices-delete", await call(app, .DELETE, "v1/devices/dev-1", token: session.accessToken))
        }
    }

    // MARK: - Nutrition (driven where possible)

    @Test func foodsSupplementsAndAliases() async throws {
        try await withApp { app in
            let session = try await login(app, name: "contract-food")
            try golden("foods-search", await call(app, .GET, "v1/foods/search?q=chicken&limit=5", token: session.accessToken))
            try golden("supplements-lookup", await call(app, .GET, "v1/supplements/lookup/012345678905", token: session.accessToken))
            try golden("supplements-picks-verified", await call(app, .GET, "v1/supplements/picks/creatine?name=creatine", token: session.accessToken))
            // Unverified (AI fallback) picks need Claude: encode the server's type, everything filled.
            let unverified = SupplementPicksDTO(
                kind: "other",
                picks: [.init(
                    brand: "Example", product: "Example Product", form: "powder",
                    certifications: ["NSF Certified for Sport"], why: "Third-party tested.",
                    approxPricePerServingUSD: 0.89, priceAsOf: "2026-09",
                    buyLinks: [.init(label: "Amazon", url: "https://example.com/p")]
                )],
                verified: false,
                lookFor: "third-party tested; 3-5 g/day"
            )
            try golden("supplements-picks-unverified", await envelopeJSON(app, unverified))

            let alias = #"{"store_chain":"publix","raw_text":"PBX CHKN BRST \#(UUID().uuidString.prefix(8))","expanded_name":"Publix chicken breast","canonical_food_name":"chicken breast","barcode":"0123456789012"}"#
            try golden("nutrition-receipt-aliases-confirm", await call(app, .POST, "v1/nutrition/receipt-aliases/confirm", token: session.accessToken, body: alias))
        }
    }

    @Test func groceryShareRoutes() async throws {
        try await withApp { app in
            let session = try await login(app, name: "contract-grocery")
            let item = #"{"id":"11111111-1111-1111-1111-111111111111","name":"Oats","quantity":2.5,"unit":"kg","category":"pantry","checked":true,"updated_at":"2026-09-30T10:00:00Z"}"#
            let put = try await call(app, .PUT, "v1/grocery/shared", token: session.accessToken, body: #"{"title":"Week list","store":"Publix","items":[\#(item)]}"#)
            try golden("grocery-shared-put", put)
            let share = try #require(JSONSerialization.jsonObject(with: put) as? [String: Any])
            let shareToken = try #require((share["data"] as? [String: Any])?["token"] as? String)
            try golden("grocery-shared-get", await call(app, .GET, "v1/grocery/shared/\(shareToken)", token: session.accessToken))
            try golden("grocery-shared-revoke", await call(app, .POST, "v1/grocery/shared/\(shareToken)/revoke", token: session.accessToken))
        }
    }

    // MARK: - Weekly plan (driven, with the real job)

    private struct StubResolver: WeeklyPlanFoodResolving {
        func resolve(_ names: [String], on _: Request) async -> [String: ResolvedNutrition?] {
            var out: [String: ResolvedNutrition?] = [:]
            for name in names {
                let food = TestFixtures.foods.first { $0.name == name }
                // Stable id: `names` comes from a Set, so its order changes per run.
                let index = TestFixtures.foods.firstIndex { $0.name == name } ?? 0
                out[name] = food.map {
                    ResolvedNutrition(fdcId: index, description: $0.name, kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, fiber: nil, sugars: nil, confidence: 0.9)
                }
            }
            return out
        }
    }

    private struct StubAI: WeeklyPlanAIClient {
        func generate(system _: String, prompt: String, on _: Request) async throws -> String {
            TestFixtures.weeklyPlanJSON(prompt: prompt)
        }
    }

    @Test func weeklyPlanRoutes() async throws {
        try await withApp { app in
            let session = try await login(app, name: "contract-plan")

            // No job yet -> `"data": null`.
            try golden("nutrition-weekly-plans-latest-none", await call(app, .GET, "v1/nutrition/weekly-plans/latest", token: session.accessToken))

            let body = """
            {"week_start":"2026-09-28","system":"You are a meal planner.","prompt":"<macro_targets_by_day_type>\\n- Strength: x\\n- Rest: y\\n</macro_targets_by_day_type>",
             "targets":{"strength":{"kcal":2800,"protein_g":180,"carbs_g":320,"fat_g":80},"rest":{"kcal":2300,"protein_g":170,"carbs_g":220,"fat_g":75}},"timezone":"America/New_York"}
            """
            let created = try await call(app, .POST, "v1/nutrition/weekly-plans", token: session.accessToken, body: body)
            try golden("nutrition-weekly-plans-post", created)
            let json = try #require(JSONSerialization.jsonObject(with: created) as? [String: Any])
            let jobIDString = try #require((json["data"] as? [String: Any])?["id"] as? String)
            let jobID = try #require(UUID(uuidString: jobIDString))

            // Run the real job (fake Claude, stub USDA) so the plan is the pipeline's real output.
            let context = app.queues.queue(.mealPlans).context
            try await WeeklyPlanJob(aiClient: StubAI(), makeResolver: { StubResolver() }).dequeue(context, jobID)

            try golden("nutrition-weekly-plans-get", await call(app, .GET, "v1/nutrition/weekly-plans/\(jobID.uuidString)", token: session.accessToken))
            try golden("nutrition-weekly-plans-latest", await call(app, .GET, "v1/nutrition/weekly-plans/latest", token: session.accessToken))

            // The job also pushed "plan ready": the real APNs payload, captured by test mode.
            let pushes = try #require(app.testMode).pushes(for: session.userID)
            let ready = try #require(pushes.last)
            try golden("push-meal_plan_ready", Data(ready.payload.utf8))
        }
    }

    // MARK: - Pushes (driven)

    @Test func otherPushes() async throws {
        try await withApp { app in
            let session = try await login(app, name: "contract-push")
            let state = try #require(app.testMode)

            // POST /v1/devices/test-push -> general alert.
            state.clearPushes(for: session.userID)
            try await call(app, .POST, "v1/devices/test-push", token: session.accessToken)
            try golden("push-general", Data(#require(state.pushes(for: session.userID).last).payload.utf8))

            // Morning briefing (what NotificationScheduleJob sends), forced past its time window.
            state.clearPushes(for: session.userID)
            try await call(app, .POST, "v1/test/jobs/run", token: nil, body: #"{"job":"morning-briefing","name":"contract-push","force":true}"#)
            try golden("push-recovery_morning", Data(#require(state.pushes(for: session.userID).last).payload.utf8))
        }
    }

    @Test func programImportQuota() async throws {
        try await withApp { app in
            let session = try await login(app, name: "contract-quota", pro: false)
            try golden("program-import-quota", await call(app, .GET, "v1/training/program-import/quota", token: session.accessToken))
        }
    }

    // MARK: - Encoded (need a Claude/OpenAI key or Apple identity)

    @Test func encodedAIRoutes() async throws {
        try await withApp { app in
            try golden("insights-training-program", await envelopeJSON(app, TrainingProgramResponse(
                weekStart: "2026-09-28",
                days: [
                    TrainingProgramDay(day: "monday", workoutType: "push", volumeAdjustment: 1.0),
                    TrainingProgramDay(day: "tuesday", workoutType: "pull", volumeAdjustment: 0.9),
                ],
                rationale: "Recovery is green, push volume stays high."
            )))
            try golden("nutrition-ai-meal-timing", await envelopeJSON(app, MealTimingResponse(suggestedTime: "13:30", note: "Protein within 90 min of training.")))
            try golden("insights-study-schedule", await envelopeJSON(app, StudyScheduleResponse(
                examId: "exam-1",
                sessions: [StudySession(dayOffset: 1, topic: "Graphs", minutes: 50)],
                rationale: "Weakest topics first."
            )))

            try golden("nutrition-ai-proxy-text", await envelopeJSON(app, NutritionProxyTextResponse(text: "{\"ok\":true}")))
            try golden("nutrition-ai-proxy-vision", await envelopeJSON(app, NutritionProxyTextResponse(text: "{\"items\":[]}")))
            try golden("nutrition-ai-explain-adjustment", await envelopeJSON(app, ExplainAdjustmentResponse(message: "Red recovery: calories trimmed 150.")))
            try golden("nutrition-ai-suggest-meal", await envelopeJSON(app, SuggestMealResponse(message: "Chicken and rice closes the protein gap.")))

            try golden("nutrition-ai-coach-chat", await envelopeJSON(app, CoachProxyChatResponse(
                content: [
                    .text("Logging that."),
                    .toolUse(id: "toolu_01", name: "log_meal", input: ["food": AnyCodable("oats"), "grams": AnyCodable(80)]),
                ],
                stopReason: "tool_use",
                usage: .init(inputTokens: 1200, outputTokens: 85),
                model: "claude-haiku-4-5"
            )))
            try golden("nutrition-ai-coach-chat-text", await envelopeJSON(app, CoachProxyChatResponse(
                content: [.text("Done. 80 g oats logged.")],
                stopReason: "end_turn",
                usage: .init(inputTokens: 1300, outputTokens: 20),
                model: "claude-haiku-4-5"
            )))

            try golden("nutrition-receipts-structure", await envelopeJSON(app, Self.receiptResponse))

            try golden("program-import-transcribe", await envelopeJSON(app, ProgramImportTranscribeResponse(pages: ["Day 1: Squat 5x5", "Day 2: Bench 5x5"])))
            try golden("program-import-structure", await envelopeJSON(app, ProgramImportStructureResponse(text: "{\"name\":\"5x5\"}")))
            try golden("program-import-feedback", await envelopeJSON(app, ProgramFeedbackResponse(text: "Solid program; add rows.")))

            try golden("exercise-images-post", await envelopeJSON(app, ExerciseImageResponseDTO.ready(slug: "barbell-squat", baseURL: "https://api.example.com")))
            try golden("grocery-instacart-cart", await envelopeJSON(app, InstacartCartResponseDTO(url: "https://www.instacart.com/store/shopping_lists/123")))
        }
    }

    private static var receiptResponse: ReceiptStructuringResponseDTO {
        ReceiptStructuringResponseDTO(
            store: "Publix",
            purchaseDate: Date(timeIntervalSince1970: 1_790_000_000),
            totalAmount: 41.27,
            taxAmount: 1.12,
            paymentMethod: "VISA",
            lineItems: [.init(
                rawText: "PBX CHKN BRST", canonicalFoodName: "chicken breast", displayName: "Chicken Breast",
                quantity: 1.2, unit: "kg", quantityGrams: 1200, unitPrice: 7.99, totalPrice: 9.59, pricePerKg: 7.99,
                onSale: true, saleNote: "BOGO", confidence: 0.93, isNonFood: false, isFee: false,
                taxFlag: "F", categoryHint: "MEAT", lineDiscount: 1.5
            )],
            confidence: 0.91,
            provider: "haiku_vision",
            notes: "Faint print at the bottom.",
            subtotalAmount: 40.15,
            savingsAmount: 6.5,
            couponTotal: 2.0,
            currency: "USD",
            storeChain: "publix"
        )
    }
}

// MARK: - Normalization

/// Turns a raw response into a stable, readable golden: sorted keys, pretty
/// printed, and every volatile value replaced by a fixed one of the SAME SHAPE
/// (so a date that gains fractional seconds, or an id that stops being a UUID,
/// still shows up).
enum ContractNormalizer {
    static func canonicalJSON(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var state = State()
        let normalized = normalize(object, state: &state)
        let out = try JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        return String(decoding: out, as: UTF8.self) + "\n"
    }

    private struct State {
        var uuids: [String: String] = [:]
        var tokens: [String: String] = [:]
    }

    private static func normalize(_ value: Any, state: inout State) -> Any {
        switch value {
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for key in dict.keys.sorted() {
                out[key] = normalize(dict[key]!, state: &state)
            }
            return out
        case let array as [Any]:
            return array.map { normalize($0, state: &state) }
        case let string as String:
            return normalizeString(string, state: &state)
        default:
            return value
        }
    }

    private static func normalizeString(_ input: String, state: inout State) -> String {
        var s = input
        // JWTs
        s = replace(s, pattern: #"eyJ[\w-]+\.[\w-]+\.[\w-]+"#) { _ in "eyJhbGciOiJIUzI1NiJ9.e30.c2ln" }
        // Prefixed random ids (rt_, req_, usr_, dt_, ...): keep prefix and length
        s = replace(s, pattern: #"\b[a-z]{2,4}_[0-9a-f]{12,}"#) { match in
            let parts = match.split(separator: "_", maxSplits: 1)
            return "\(parts[0])_" + String(repeating: "0", count: parts[1].count)
        }
        // UUIDs: stable per first appearance
        s = replace(s, pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#) { match in
            let key = match.lowercased()
            if let known = state.uuids[key] {
                return known
            }
            let fixed = String(format: "00000000-0000-0000-0000-%012d", state.uuids.count + 1)
            state.uuids[key] = fixed
            return fixed
        }
        // Share tokens (20-40 hex chars)
        s = replace(s, pattern: #"(?<![0-9a-f])[0-9a-f]{20,40}(?![0-9a-f])"#) { match in
            if let known = state.tokens[match] {
                return known
            }
            let fixed = String(format: "%0\(match.count)d", state.tokens.count + 1)
            state.tokens[match] = fixed
            return fixed
        }
        // ISO-8601 timestamps, keeping whether they carry fractional seconds
        s = replace(s, pattern: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})"#) { match in
            match.contains(".") ? "2026-01-01T00:00:00.000Z" : "2026-01-01T00:00:00Z"
        }
        // Random test usernames
        s = replace(s, pattern: #"test_[a-z0-9_]+_\d{4}"#) { _ in "test_user_0000" }
        return s
    }

    private static func replace(_ input: String, pattern: String, _ transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += transform(ns.substring(with: match.range))
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }
}
