@testable import App
import Fluent
import Foundation
import Testing
import Vapor
@preconcurrency import Redis

// MARK: - Fakes

struct FakeCoachSource: CoachWorkoutSource {
    let all: [CoachSession]
    func sessions(for _: String, from: Date, to: Date, on _: Request) async throws -> [CoachSession] {
        all.filter { $0.end >= from && $0.start <= to }
    }
}

struct FakeWeather: WeatherProviding {
    var result: WeatherConditions?
    var fails = false
    func conditions(latitude _: Double, longitude _: Double, from _: Date, to _: Date, on _: Request) async throws -> WeatherConditions? {
        if fails { throw Abort(.badGateway) }
        return result
    }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func session(
    id: String = "1", start: Date = t0, minutes: Double = 80, kJ: Double? = 3500, strain: Double? = 14.8
) -> CoachSession {
    CoachSession(id: id, start: start, end: start.addingTimeInterval(minutes * 60), sportName: "soccer", strain: strain,
                 kilojoules: kJ, averageHeartRate: 150, percentRecorded: 100)
}

private func record(
    start: String = "2026-11-20T18:00:00.000Z", end: String = "2026-11-20T19:20:00.000Z",
    state: String = "SCORED", kJ: Double? = 3500
) -> WhoopV2WorkoutRecord {
    WhoopV2WorkoutRecord(
        id: "ecfc6a15-4661-442f-a9a4-f160dd7afae8", v1Id: 42, userId: 1, start: start, end: end, timezoneOffset: "-05:00",
        sportName: "soccer", scoreState: state,
        score: WhoopV2WorkoutScore(strain: 14.8, averageHeartRate: 150, maxHeartRate: 186, kilojoule: kJ, percentRecorded: 100)
    )
}

// MARK: - Session rules

@Suite("Coach session rules")
struct CoachSessionRulesTests {
    @Test func scoredRecordBecomesASessionWithFractionalDates() throws {
        let s = try #require(CoachSessionRules.session(from: record()))
        #expect(s.id == "ecfc6a15-4661-442f-a9a4-f160dd7afae8" && s.durationMinutes == 80 && s.sportName == "soccer")
        #expect(abs(try #require(s.kilocalories) - 3500 / 4.184) < 1e-9)
    }

    @Test func unscoredOrEnergylessRecordsAreIgnored() {
        #expect(CoachSessionRules.session(from: record(state: "PENDING_SCORE")) == nil)
        #expect(CoachSessionRules.session(from: record(state: "UNSCORABLE")) == nil)
        #expect(CoachSessionRules.session(from: record(kJ: nil)) == nil)
        #expect(CoachSessionRules.session(from: record(start: "garbage")) == nil)
        #expect(CoachSessionRules.session(from: record(start: "2026-11-20T19:20:00Z", end: "2026-11-20T18:00:00Z")) == nil)
    }

    @Test func plainDatesWithoutMillisecondsAlsoParse() {
        #expect(CoachSessionRules.parseWhoopDate("2026-11-20T18:00:00Z") != nil)
        #expect(CoachSessionRules.parseWhoopDate("2026-11-20T18:00:00.123Z") != nil)
    }

    @Test func thresholdsAreTwentyMinutesAndOneFiftyKilocalories() {
        #expect(CoachSessionRules.qualifies(session(minutes: 20, kJ: 628.0))) // 150.1 kcal
        #expect(!CoachSessionRules.qualifies(session(minutes: 19, kJ: 3500)))
        #expect(!CoachSessionRules.qualifies(session(minutes: 60, kJ: 620))) // 148 kcal
        #expect(!CoachSessionRules.qualifies(session(kJ: nil)))
    }

    @Test func notifiableOnlyBetweenTwoMinutesAndFourHoursAfterTheEnd() {
        let s = session() // ends t0 + 80 min
        #expect(!CoachSessionRules.isNotifiable(s, now: s.end.addingTimeInterval(60)))
        #expect(CoachSessionRules.isNotifiable(s, now: s.end.addingTimeInterval(180)))
        #expect(CoachSessionRules.isNotifiable(s, now: s.end.addingTimeInterval(4 * 3600)))
        #expect(!CoachSessionRules.isNotifiable(s, now: s.end.addingTimeInterval(4 * 3600 + 1)))
    }

    @Test func pushCopyStatesDurationAndStrain() {
        let text = CoachWorkoutWatch.message(for: session())
        #expect(text.title == "Session done. Weigh in now.")
        #expect(text.body.hasPrefix("80 min, strain 14.8."))
        #expect(CoachWorkoutWatch.message(for: session(strain: nil)).body.hasPrefix("80 min."))
    }
}

// MARK: - Weather

@Suite("Weather math")
struct WeatherMathTests {
    @Test func coordinatesAreRoundedToAboutElevenKilometres() {
        #expect(WeatherMath.roundedCoordinate(25.76449) == 25.8)
        #expect(WeatherMath.roundedCoordinate(-80.19607) == -80.2)
        #expect(WeatherMath.roundedCoordinate(44.5736) == 44.6)
    }

    @Test func averagesTheHoursTouchingTheSession() throws {
        let h0 = WeatherMath.floorToHour(t0)
        let hours = (0 ..< 4).map { WeatherHour(time: h0.addingTimeInterval(Double($0) * 3600), temperatureC: 20 + Double($0), relativeHumidityPercent: 60) }
        // session t0 ... t0+80 min touches the hour of t0 and the next one (and the third if it starts inside it)
        let w = try #require(WeatherMath.average(hours, from: t0, to: t0.addingTimeInterval(80 * 60)))
        #expect(w.relativeHumidityPercent == 60)
        #expect(w.temperatureC >= 20 && w.temperatureC <= 22)
        #expect(WeatherMath.average([], from: t0, to: t0.addingTimeInterval(60)) == nil)
    }

    @Test func parsesOpenMeteoAndSkipsNullHours() throws {
        let json = #"{"hourly":{"time":["2026-11-20T14:00","2026-11-20T15:00","2026-11-20T16:00"],"temperature_2m":[27.1,null,26.0],"relative_humidity_2m":[70,71,null]}}"#
        let hours = try WeatherMath.parseOpenMeteo(Data(json.utf8))
        #expect(hours.count == 1)
        #expect(hours[0].temperatureC == 27.1 && hours[0].relativeHumidityPercent == 70)
    }

    @Test func testFixtureIsValidOpenMeteoJSONForTheTestServer() throws {
        let hours = try WeatherMath.parseOpenMeteo(Data(TestFixtures.openMeteo(now: t0).utf8))
        #expect(hours.count == 96)
        #expect(WeatherMath.average(hours, from: t0.addingTimeInterval(-3600), to: t0)?.temperatureC == 27.5)
    }
}

// MARK: - Engine

@Suite("Coach recovery engine")
struct CoachRecoveryEngineTests {
    private func w(_ minutes: Double, _ kg: Double, _ source: String = "withings") -> CoachWeighInDTO {
        CoachWeighInDTO(time: t0.addingTimeInterval(minutes * 60), kg: kg, source: source)
    }

    private func request(
        weighIns: [CoachWeighInDTO], drank: Double? = 0.5, urine: Double? = 0, body: Double? = nil,
        hours: Double? = nil, scaleSd: Double? = nil
    ) -> CoachRecoveryRequest {
        CoachRecoveryRequest(sessionId: "1", sessionStart: t0, weighIns: weighIns, drankLiters: drank, urineLiters: urine,
                             hoursUntilNextHardSession: hours, latitude: nil, longitude: nil, bodyMassKg: body, scaleRepeatabilitySdKg: scaleSd)
    }

    @Test func readyWhenPreAndPostExist() throws {
        let r = try CoachRecoveryEngine.compute(
            session: session(), request: request(weighIns: [w(-10, 78.0), w(95, 76.8)]),
            weather: WeatherConditions(temperatureC: 27, relativeHumidityPercent: 70)
        )
        #expect(r.status == "ready" && r.missing.isEmpty)
        let sweat = try #require(r.sweat)
        #expect(abs(sweat.massLostKg - 1.2) < 1e-9)
        #expect(try #require(sweat.sweatLitersLow) < #require(sweat.sweatLitersHigh))
        #expect(sweat.protocolQuality == "tight")
        let plan = try #require(r.plan)
        #expect(plan.drinkLiters != nil && plan.proteinGrams >= 20 && plan.carbsGrams > 0)
        #expect(plan.reasons.contains { $0.contains("with a meal") })
    }

    @Test func listsWhichWeighInIsMissing() throws {
        let onlyPre = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 78.0)]), weather: nil)
        #expect(onlyPre.status == "needs_weigh_in" && onlyPre.missing == ["post_weigh_in"])
        let none = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: []), weather: nil)
        #expect(none.missing == ["pre_weigh_in", "post_weigh_in"])
        #expect(none.sweat == nil && none.plan == nil, "no body mass, no weigh-ins: nothing to base macros on")
    }

    @Test func macrosStillComeBackWithOnlyABodyMass() throws {
        let r = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [], body: 78), weather: nil)
        let plan = try #require(r.plan)
        #expect(plan.drinkLiters == nil && plan.sodiumMgPlan == nil, "no measured sweat, no fluid or sodium advice")
        #expect(plan.proteinGrams > 0)
    }

    @Test func implausibleLossAsksForAReweigh() throws {
        let up = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 78.0), w(95, 78.8)]), weather: nil)
        #expect(up.status == "implausible" && up.sweat?.sweatLitersLow == nil)
        let huge = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 78.0), w(95, 74.0)]), weather: nil)
        #expect(huge.status == "implausible")
    }

    @Test func unknownFluidsAreFlaggedAsAMinimum() throws {
        let r = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 78.0), w(95, 76.8)], drank: nil), weather: nil)
        #expect(r.sweat?.isLowerBound == true && r.sweat?.meetsFivePercentTarget == false)
    }

    @Test func measuredScaleRepeatabilityShowsUpInTheAssumptions() throws {
        let r = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 78.0), w(95, 75.8)], scaleSd: 0.02), weather: nil)
        #expect(r.sweat?.assumptions.contains { $0.contains("measured on your own scale") } == true)
    }

    @Test func rapidRefuelIsPassedThrough() throws {
        let rapid = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 78.0), w(95, 76.8)], hours: 3), weather: nil)
        #expect(rapid.plan?.carbWindowHours == 4)
        let relaxed = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 78.0), w(95, 76.8)], hours: 24), weather: nil)
        #expect(relaxed.plan?.carbWindowHours == 2)
    }

    @Test func rejectsNonsenseInput() {
        #expect(throws: CoachRecoveryEngine.ValidationError.weightOutOfRange) {
            try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 5)]), weather: nil)
        }
        #expect(throws: CoachRecoveryEngine.ValidationError.weightOutOfRange) {
            try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [], body: 900), weather: nil)
        }
        #expect(throws: CoachRecoveryEngine.ValidationError.fluidOutOfRange) {
            try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [], drank: 25), weather: nil)
        }
        #expect(throws: CoachRecoveryEngine.ValidationError.tooManyWeighIns) {
            try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: Array(repeating: w(-10, 78), count: 201)), weather: nil)
        }
    }

    @Test func weatherChangesTheNonSweatTermOnlyALittle() throws {
        let hot = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 80.0), w(95, 77.5)]),
                                                  weather: WeatherConditions(temperatureC: 33, relativeHumidityPercent: 30))
        let humid = try CoachRecoveryEngine.compute(session: session(), request: request(weighIns: [w(-10, 80.0), w(95, 77.5)]),
                                                    weather: WeatherConditions(temperatureC: 27, relativeHumidityPercent: 85))
        let a = try #require(hot.sweat?.sweatLitersMid), b = try #require(humid.sweat?.sweatLitersMid)
        #expect(abs(a - b) < 0.1, "weather moves the sweat estimate by under 0.1 L")
        #expect(a < b, "dry hot air takes more water out through breathing, so less of the loss is sweat")
    }
}

// MARK: - Endpoints and push (in-process app, test mode)

@Suite("Coach endpoints and push", .serialized)
struct CoachEndpointTests {
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

    private static let deviceID = "coach-device"
    private struct Login { let token: String; let userID: String }

    private func login(_ app: Application, _ name: String) async throws -> Login {
        var out: Login?
        try await app.test(.POST, "v1/test/login", beforeRequest: { req in
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: "X-Device-Id", value: Self.deviceID)
            req.body = ByteBuffer(string: #"{"name":"\#(name)","fresh":true,"pro":true}"#)
        }, afterResponse: { res async throws in
            let b = try res.content.decode(TestModeController.LoginResponse.self)
            out = Login(token: b.accessToken, userID: b.userId)
        })
        return try #require(out)
    }

    private func send(_ app: Application, _ method: HTTPMethod, _ path: String, token: String, body: String? = nil) async throws -> (HTTPStatus, Data) {
        var status = HTTPStatus.ok
        var data = Data()
        try await app.test(method, path, beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: token)
            req.headers.replaceOrAdd(name: "X-Device-Id", value: Self.deviceID)
            if let body { req.headers.contentType = .json; req.body = ByteBuffer(string: body) }
        }, afterResponse: { res async throws in
            status = res.status
            data = Data(res.body.readableBytesView)
        })
        return (status, data)
    }

    private func iso(_ d: Date) -> String { CoachSessionRules.whoopTimestamp(d) }

    /// A match that ended 10 minutes ago plus a short walk, with a fresh random id so Redis keys never collide.
    private func fixtures(now: Date) -> (match: CoachSession, walk: CoachSession) {
        let base = UUID().uuidString
        let matchEnd = now.addingTimeInterval(-600)
        let walkEnd = now.addingTimeInterval(-5 * 3600)
        return (
            CoachSession(id: "match-" + base, start: matchEnd.addingTimeInterval(-80 * 60), end: matchEnd, sportName: "soccer", strain: 14.8, kilojoules: 3500, averageHeartRate: 150, percentRecorded: 100),
            CoachSession(id: "walk-" + base, start: walkEnd.addingTimeInterval(-15 * 60), end: walkEnd, sportName: "walking", strain: 3.1, kilojoules: 180, averageHeartRate: 90, percentRecorded: 100)
        )
    }

    @Test func recentSessionsListsOnlyBigFinishedWorkouts() async throws {
        try await withApp { app in
            let f = fixtures(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [f.match, f.walk])
            let me = try await login(app, "coach-recent")
            let (status, data) = try await send(app, .GET, "v1/coach/sessions/recent", token: me.token)
            #expect(status == .ok)
            let text = String(decoding: data, as: UTF8.self)
            #expect(text.contains("\"id\":\"\(f.match.id)\"") && !text.contains("\"id\":\"\(f.walk.id)\""))
            #expect(text.contains("\"sport_name\":\"soccer\"") && text.contains("\"kilojoules\":3500"))
        }
    }

    @Test func recoveryEndpointReturnsASweatEstimateAndPlan() async throws {
        try await withApp { app in
            let f = fixtures(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [f.match])
            app.weatherProvider = FakeWeather(result: WeatherConditions(temperatureC: 27.5, relativeHumidityPercent: 72))
            let me = try await login(app, "coach-recovery")
            let pre = f.match.start.addingTimeInterval(-600), post = f.match.end.addingTimeInterval(300)
            let body = #"{"session_id":"\#(f.match.id)","session_start":"\#(iso(f.match.start))","weigh_ins":[{"time":"\#(iso(pre))","kg":78.0,"source":"withings"},{"time":"\#(iso(post))","kg":76.8,"source":"withings"}],"drank_liters":0.5,"urine_liters":0,"latitude":25.7645,"longitude":-80.1961}"#
            let (status, data) = try await send(app, .POST, "v1/coach/recovery", token: me.token, body: body)
            #expect(status == .ok, "\(String(decoding: data, as: UTF8.self).prefix(300))")
            let text = String(decoding: data, as: UTF8.self)
            #expect(text.contains("\"status\":\"ready\"") && text.contains("\"mass_lost_kg\":1.2") && text.contains("\"drink_liters\""))
            #expect(text.contains("\"protocol_quality\":\"tight\""))
        }
    }

    @Test func missingPostWeighInSaysSo() async throws {
        try await withApp { app in
            let f = fixtures(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [f.match])
            app.weatherProvider = FakeWeather(result: nil)
            let me = try await login(app, "coach-missing")
            let pre = f.match.start.addingTimeInterval(-600)
            let body = #"{"session_id":"\#(f.match.id)","session_start":"\#(iso(f.match.start))","weigh_ins":[{"time":"\#(iso(pre))","kg":78.0,"source":"manual"}]}"#
            let (status, data) = try await send(app, .POST, "v1/coach/recovery", token: me.token, body: body)
            #expect(status == .ok)
            let text = String(decoding: data, as: UTF8.self)
            #expect(text.contains("\"status\":\"needs_weigh_in\"") && text.contains("\"post_weigh_in\""))
        }
    }

    @Test func weatherFailureNeverFailsTheRequest() async throws {
        try await withApp { app in
            let f = fixtures(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [f.match])
            app.weatherProvider = FakeWeather(result: nil, fails: true)
            let me = try await login(app, "coach-weather-fail")
            let pre = f.match.start.addingTimeInterval(-600), post = f.match.end.addingTimeInterval(300)
            let body = #"{"session_id":"\#(f.match.id)","session_start":"\#(iso(f.match.start))","weigh_ins":[{"time":"\#(iso(pre))","kg":78.0,"source":"withings"},{"time":"\#(iso(post))","kg":76.8,"source":"withings"}],"latitude":25.8,"longitude":-80.2}"#
            let (status, data) = try await send(app, .POST, "v1/coach/recovery", token: me.token, body: body)
            #expect(status == .ok && String(decoding: data, as: UTF8.self).contains("\"status\":\"ready\""))
        }
    }

    @Test func unknownSessionIs404AndBadWeightIs422() async throws {
        try await withApp { app in
            let f = fixtures(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [f.match])
            let me = try await login(app, "coach-errors")
            let unknown = #"{"session_id":"nope","session_start":"\#(iso(f.match.start))","weigh_ins":[]}"#
            #expect(try await send(app, .POST, "v1/coach/recovery", token: me.token, body: unknown).0 == .notFound)
            let bad = #"{"session_id":"\#(f.match.id)","session_start":"\#(iso(f.match.start))","weigh_ins":[{"time":"\#(iso(f.match.start))","kg":5,"source":"manual"}]}"#
            #expect(try await send(app, .POST, "v1/coach/recovery", token: me.token, body: bad).0 == .unprocessableEntity)
            #expect(try await send(app, .GET, "v1/coach/sessions/recent", token: "not-a-token").0 == .unauthorized)
        }
    }

    @Test func finishedMatchSendsExactlyOneWeighInPush() async throws {
        try await withApp { app in
            let f = fixtures(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [f.match, f.walk])
            let me = try await login(app, "coach-push")
            let first = try await CoachWorkoutWatch().check(userID: me.userID, app: app, now: app.now, requireDevice: false)
            let second = try await CoachWorkoutWatch().check(userID: me.userID, app: app, now: app.now, requireDevice: false)
            #expect(first == 1, "the big match notifies, the short walk does not")
            #expect(second == 0, "a session is only ever announced once")
            let pushes = try #require(app.testMode?.pushes(for: me.userID))
            #expect(pushes.count == 1)
            let payload = pushes[0].payload
            #expect(payload.contains("post_workout_weighin") && payload.contains("POST_WORKOUT_WEIGHIN"))
            #expect(payload.contains("\(f.match.id)") && payload.contains("Weigh in now"))
        }
    }

    @Test func tooEarlyOrTooLateSendsNothing() async throws {
        try await withApp { app in
            let now = app.now
            let justEnded = CoachSession(id: "just-" + UUID().uuidString, start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-30), sportName: "soccer", strain: 12, kilojoules: 3000, averageHeartRate: 150, percentRecorded: 100)
            let longAgo = CoachSession(id: "late-" + UUID().uuidString, start: now.addingTimeInterval(-9 * 3600), end: now.addingTimeInterval(-7 * 3600), sportName: "soccer", strain: 12, kilojoules: 3000, averageHeartRate: 150, percentRecorded: 100)
            app.coachWorkoutSource = FakeCoachSource(all: [justEnded, longAgo])
            let me = try await login(app, "coach-window")
            let sent = try await CoachWorkoutWatch().check(userID: me.userID, app: app, now: now, requireDevice: false)
            #expect(sent == 0)
        }
    }

    @Test func userWithoutADeviceIsSkippedUnlessForced() async throws {
        try await withApp { app in
            let f = fixtures(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [f.match])
            let me = try await login(app, "coach-nodevice")
            #expect(try await CoachWorkoutWatch().check(userID: me.userID, app: app, now: app.now, requireDevice: true) == 0)
        }
    }

    @Test func testServerHasAStableFinishedMatchAndTheJobRunsForANamedUser() async throws {
        try await withApp { app in
            // No override: the test server's own fixture source.
            let me = try await login(app, "coach-testserver")
            let (status, data) = try await send(app, .GET, "v1/coach/sessions/recent", token: me.token)
            #expect(status == .ok)
            let text = String(decoding: data, as: UTF8.self)
            #expect(text.contains("\"kilojoules\":3500") && !text.contains("\"kilojoules\":180"), "the match, not the short walk")

            func runJob() async throws -> Int? {
                var affected: Int?
                try await app.test(.POST, "v1/test/jobs/run", beforeRequest: { req in
                    req.headers.contentType = .json
                    req.body = ByteBuffer(string: #"{"job":"coach-workout-watch","name":"coach-testserver"}"#)
                }, afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    affected = try res.content.decode(TestModeController.JobResponse.self).affected
                })
                return affected
            }
            // Redis remembers a notified session for 3 days: forget this hour's test match so the run is repeatable.
            let hour = Int64((app.now.timeIntervalSince1970 / 3600).rounded(.down))
            _ = try await app.redis.delete(RedisKey("coach:notified:\(me.userID):test-match-\(hour)")).get()
            #expect(try await runJob() == 1, "the first run announces the match")
            #expect(app.testMode?.pushes(for: me.userID).count == 1)
            #expect(try await runJob() == 0, "a second run inside the hour announces nothing")
            #expect(app.testMode?.pushes(for: me.userID).count == 1)
        }
    }

    @Test func sweepFindsEveryUserWithAConnectedWhoop() async throws {
        try await withApp { app in
            let f = fixtures(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [f.match])
            let me = try await login(app, "coach-sweep")
            let integration = WhoopIntegration(userID: me.userID, encryptedAccessToken: "x", encryptedRefreshToken: "y", tokenExpiresAt: Date().addingTimeInterval(3600), whoopUserID: String(Int.random(in: 1 ... 999_999_999)))
            try await integration.save(on: app.db)
            let sent = try await CoachWorkoutWatchJob().sweep(app: app, now: app.now, userID: me.userID)
            #expect(sent == 1)
            try await integration.delete(on: app.db)
        }
    }
}


// MARK: - Push failure and overlap

@Suite("Coach push reliability", .serialized)
struct CoachPushReliabilityTests {
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

    private func freshMatch(now: Date) -> CoachSession {
        CoachSession(id: "rel-" + UUID().uuidString, start: now.addingTimeInterval(-90 * 60), end: now.addingTimeInterval(-10 * 60),
                     sportName: "soccer", strain: 14.8, kilojoules: 3500, averageHeartRate: 150, percentRecorded: 100)
    }

    @Test func aPushThatReachesNoDeviceIsRetriedNotLost() async throws {
        try await withApp { app in
            let match = freshMatch(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [match])
            let uid = "rel-user-" + UUID().uuidString
            var watch = CoachWorkoutWatch()
            watch.send = { _, _, _, _, _ in 0 } // APNs down: nothing delivered
            let whileDown = try await watch.check(userID: uid, app: app, now: app.now, requireDevice: false)
            watch.send = { _, _, _, _, _ in 1 } // APNs back
            let afterRecovery = try await watch.check(userID: uid, app: app, now: app.now, requireDevice: false)
            let afterThat = try await watch.check(userID: uid, app: app, now: app.now, requireDevice: false)
            #expect(whileDown == 0)
            #expect(afterRecovery == 1, "the next sweep retries")
            #expect(afterThat == 0, "and then it is final")
        }
    }

    @Test func aThrowingSenderIsAlsoRetried() async throws {
        try await withApp { app in
            let match = freshMatch(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [match])
            let uid = "rel-throw-" + UUID().uuidString
            var watch = CoachWorkoutWatch()
            watch.send = { _, _, _, _, _ in throw Abort(.badGateway) }
            let failing = try await watch.check(userID: uid, app: app, now: app.now, requireDevice: false)
            watch.send = { _, _, _, _, _ in 1 }
            let recovered = try await watch.check(userID: uid, app: app, now: app.now, requireDevice: false)
            #expect(failing == 0)
            #expect(recovered == 1)
        }
    }

    @Test func overlappingChecksSendExactlyOnePush() async throws {
        try await withApp { app in
            let match = freshMatch(now: app.now)
            app.coachWorkoutSource = FakeCoachSource(all: [match])
            let uid = "rel-race-" + UUID().uuidString
            let counter = PushCounter()
            var watch = CoachWorkoutWatch()
            watch.send = { _, _, _, _, _ in
                await counter.increment()
                try await Task.sleep(for: .milliseconds(50)) // widen the window in which a race would show
                return 1
            }
            let now = app.now
            let sent = try await withThrowingTaskGroup(of: Int.self) { group in
                for _ in 0 ..< 6 { group.addTask { [watch] in try await watch.check(userID: uid, app: app, now: now, requireDevice: false) } }
                var total = 0
                for try await n in group { total += n }
                return total
            }
            #expect(sent == 1)
            #expect(await counter.value == 1, "six simultaneous checks, one push")
        }
    }
}

actor PushCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
