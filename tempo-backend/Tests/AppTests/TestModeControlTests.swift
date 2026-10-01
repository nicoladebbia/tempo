@testable import App
import Fluent
import Foundation
import Redis
import Testing
import Vapor
import XCTVapor

// Faults, short tokens, sign-out, the test clock, run-now jobs and
// subscription states (scripts/testenv.sh fault | auth | sign-out | time | job | sub).

@Suite("TestMode controls", .serialized)
struct TestModeControlTests {
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

    private struct Session {
        let name: String
        let userID: String
        let access: String
        let refresh: String
    }

    private func login(_ app: Application, pro: Bool = true, extra: String = "") async throws -> Session {
        let name = "c-\(UUID().uuidString.prefix(8).lowercased())"
        var session: Session?
        try await app.test(.POST, "v1/test/login", beforeRequest: { req in
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: "X-Device-Id", value: "sim-\(name)")
            req.body = ByteBuffer(string: #"{"name":"\#(name)","pro":\#(pro)\#(extra)}"#)
        }, afterResponse: { res async throws in
            #expect(res.status == .ok)
            let body = try res.content.decode(TestModeController.LoginResponse.self)
            session = Session(name: name, userID: body.userId, access: body.accessToken, refresh: body.refreshToken)
        })
        return try #require(session)
    }

    private func post(_ app: Application, _ path: String, _ json: String, _ check: @escaping (XCTHTTPResponse) async throws -> Void = { _ in }) async throws {
        try await app.test(.POST, path, beforeRequest: { req in
            req.headers.contentType = .json
            req.body = ByteBuffer(string: json)
        }, afterResponse: { res async throws in try await check(res) })
    }

    /// Status of a Pro + consent gated route.
    private func weeklyReport(_ app: Application, _ session: Session) async throws -> HTTPStatus {
        var status: HTTPStatus = .internalServerError
        try await app.test(.GET, "v1/insights/weekly-report", beforeRequest: { req in
            req.headers.bearerAuthorization = .init(token: session.access)
        }, afterResponse: { res async in status = res.status })
        return status
    }

    // MARK: Faults

    @Test func faultsBreakMatchingRequestsThenStop() async throws {
        try await withApp { app in
            let me = try await login(app)
            let other = try await login(app)
            try await post(app, "v1/test/faults", #"{"path_prefix":"/v1/insights","kind":"error","status":503,"remaining":2,"user_id":"\#(me.userID)"}"#) { res in
                #expect(res.status == .ok)
            }
            #expect(try await weeklyReport(app, other) == .ok)  // someone else: untouched
            #expect(try await weeklyReport(app, me) == .serviceUnavailable)
            #expect(try await weeklyReport(app, me) == .serviceUnavailable)
            #expect(try await weeklyReport(app, me) == .ok)  // count used up
            #expect(app.testMode?.faults.all.isEmpty == true)

            try await post(app, "v1/test/faults", #"{"path_prefix":"/v1/insights","kind":"logout"}"#)
            #expect(try await weeklyReport(app, me) == .unauthorized)
            try await post(app, "v1/test/faults", #"{"path_prefix":"/v1/test","kind":"error"}"#) { res in
                #expect(res.status == .badRequest)  // the controls can't break themselves
            }
            try await app.test(.DELETE, "v1/test/faults", afterResponse: { res async throws in #expect(res.status == .noContent) })
            #expect(try await weeklyReport(app, me) == .ok)
        }
    }

    @Test func garbageAndEmptyFaultsAnswer200WithUnreadableBodies() async throws {
        try await withApp { app in
            let me = try await login(app)
            try await post(app, "v1/test/faults", #"{"path_prefix":"/v1/insights","kind":"garbage","remaining":1}"#)
            try await post(app, "v1/test/faults", #"{"path_prefix":"/v1/xp","kind":"empty","remaining":1}"#)
            try await app.test(.GET, "v1/insights/weekly-report", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: me.access)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                #expect((try? JSONSerialization.jsonObject(with: Data(res.body.readableBytesView))) == nil)
            })
            try await app.test(.GET, "v1/xp/today", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: me.access)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                #expect(res.body.readableBytes == 0)
            })
        }
    }

    // MARK: Auth

    @Test func shortTokensAndSignOut() async throws {
        try await withApp { app in
            try await post(app, "v1/test/auth", #"{"access_ttl_seconds":10}"#)
            let me = try await login(app)
            try await app.test(.POST, "v1/auth/refresh", beforeRequest: { req in
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: "X-Device-Id", value: "sim-\(me.name)")
                req.body = ByteBuffer(string: #"{"refresh_token":"\#(me.refresh)"}"#)
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                #expect(res.body.string.contains(#""expires_in":10"#))
            })
            try await post(app, "v1/test/auth", #"{"access_ttl_seconds":0}"#) { res in
                #expect(res.body.string.contains("900"))
            }

            let other = try await login(app)
            try await app.test(.POST, "v1/test/sign-out?name=\(other.name)", afterResponse: { res async throws in #expect(res.status == .noContent) })
            try await app.test(.POST, "v1/auth/refresh", beforeRequest: { req in
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: "X-Device-Id", value: "sim-\(other.name)")
                req.body = ByteBuffer(string: #"{"refresh_token":"\#(other.refresh)"}"#)
            }, afterResponse: { res async throws in
                #expect(res.status == .unauthorized)
            })
        }
    }

    // MARK: Clock

    @Test func clockMovesBusinessTimeOnly() async throws {
        try await withApp { app in
            let target = Date().addingTimeInterval(5 * 86400)
            try await post(app, "v1/test/clock", #"{"set":"\#(ISO8601DateFormatter().string(from: target))"}"#) { res in
                #expect(res.status == .ok)
            }
            #expect(abs(app.now.timeIntervalSince(target)) < 5)
            try await post(app, "v1/test/clock", #"{"advance_seconds":3600}"#)
            #expect(abs(app.now.timeIntervalSince(target) - 3600) < 5)
            try await post(app, "v1/test/clock", "{}") { res in #expect(res.status == .badRequest) }
            try await post(app, "v1/test/clock", #"{"reset":true}"#)
            #expect(abs(app.now.timeIntervalSinceNow) < 1)
        }
    }

    @Test func cancelledProRunsOutWhenTheClockPassesItsEnd() async throws {
        try await withApp { app in
            let me = try await login(app)
            #expect(try await weeklyReport(app, me) == .ok)  // also caches Pro for 5 min
            try await post(app, "v1/test/subscription", #"{"name":"\#(me.name)","state":"cancelled","days":2}"#) { res in
                let body = try res.content.decode(TestModeController.SubscriptionResponse.self)
                #expect(body.pro)
            }
            try await post(app, "v1/test/clock", #"{"advance_seconds":\#(3 * 86400)}"#)
            #expect(try await weeklyReport(app, me) == .paymentRequired)  // cache dropped on the clock change
            try await post(app, "v1/test/clock", #"{"reset":true}"#)
            #expect(try await weeklyReport(app, me) == .ok)
        }
    }

    @Test(arguments: [
        ("free", false), ("trial", true), ("active", true), ("cancelled", true),
        ("grace", true), ("billing-retry", false), ("expired", false), ("refunded", false),
    ])
    func subscriptionStates(state: String, pro: Bool) async throws {
        try await withApp { app in
            let me = try await login(app)
            try await post(app, "v1/test/subscription", #"{"name":"\#(me.name)","state":"\#(state)"}"#) { res in
                #expect(res.status == .ok)
                let body = try res.content.decode(TestModeController.SubscriptionResponse.self)
                #expect(body.pro == pro)
            }
            #expect(try await weeklyReport(app, me) == (pro ? .ok : .paymentRequired))
        }
    }

    @Test func unknownSubscriptionStateOrUser() async throws {
        try await withApp { app in
            let me = try await login(app)
            try await post(app, "v1/test/subscription", #"{"name":"\#(me.name)","state":"vip"}"#) { res in
                #expect(res.status == .badRequest)
            }
            try await post(app, "v1/test/subscription", #"{"name":"nobody-here","state":"free"}"#) { res in
                #expect(res.status == .notFound)
            }
        }
    }

    // MARK: Jobs

    private func briefing(_ app: Application, _ session: Session, force: Bool = false) async throws -> Int? {
        var affected: Int?
        try await post(app, "v1/test/jobs/run", #"{"job":"morning-briefing","name":"\#(session.name)","force":\#(force)}"#) { res in
            #expect(res.status == .ok)
            affected = try res.content.decode(TestModeController.JobResponse.self).affected
        }
        return affected
    }

    /// Next `hour:minute` in `zone` that's at least a day ahead (a fresh date → fresh once-a-day key).
    private func setClock(_ app: Application, hour: Int, minute: Int, zone: String, daysAhead: Int) async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        let day = calendar.date(byAdding: .day, value: daysAhead, to: Date())!
        let target = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        try await post(app, "v1/test/clock", #"{"set":"\#(ISO8601DateFormatter().string(from: target))"}"#)
    }

    @Test func morningBriefingFiresInItsWindowOncePerDay() async throws {
        try await withApp { app in
            let me = try await login(app, extra: #","timezone":"Europe/Rome""#)
            let daysAhead = Int.random(in: 30 ... 3000)
            try await setClock(app, hour: 8, minute: 20, zone: "Europe/Rome", daysAhead: daysAhead)
            #expect(try await briefing(app, me) == 1)
            #expect(try await briefing(app, me) == 0)  // already had today's
            #expect(try await briefing(app, me, force: true) == 1)
            #expect(app.testMode?.pushes(for: me.userID).count == 2)

            try await setClock(app, hour: 8, minute: 55, zone: "Europe/Rome", daysAhead: daysAhead + 1)
            #expect(try await briefing(app, me) == 0)  // outside 08:15–08:45
            try await setClock(app, hour: 8, minute: 44, zone: "Europe/Rome", daysAhead: daysAhead + 1)
            #expect(try await briefing(app, me) == 1)
            try await post(app, "v1/test/clock", #"{"reset":true}"#)
        }
    }

    @Test func weeklySummaryCachesOncePerWeek() async throws {
        try await withApp { app in
            let me = try await login(app)
            // A far-off week no other run has cached.
            try await post(app, "v1/test/clock", #"{"advance_seconds":\#(Double(Int.random(in: 500 ... 5000)) * 7 * 86400)}"#)
            for expected in [1, 0] {
                try await post(app, "v1/test/jobs/run", #"{"job":"weekly-summary","name":"\#(me.name)"}"#) { res in
                    let affected = try res.content.decode(TestModeController.JobResponse.self).affected
                    #expect(affected == expected)
                }
            }
            try await post(app, "v1/test/clock", #"{"reset":true}"#)
        }
    }

    @Test func otherJobsRunAndUnknownJobsAreRejected() async throws {
        try await withApp { app in
            for job in ["leaderboard-refresh", "notifications-cleanup", "drill-sergeant"] {
                try await post(app, "v1/test/jobs/run", #"{"job":"\#(job)"}"#) { res in
                    #expect(res.status == .ok, "\(job): \(res.body.string)")
                }
            }
            try await post(app, "v1/test/jobs/run", #"{"job":"nope"}"#) { res in #expect(res.status == .badRequest) }
            try await post(app, "v1/test/jobs/run", #"{"job":"weekly-summary","name":"nobody-here"}"#) { res in
                #expect(res.status == .notFound)
            }
        }
    }

    // MARK: Control page

    @Test func controlPageRunsUnderItsOwnNonceCSP() async throws {
        try await withApp { app in
            try await app.test(.GET, "v1/test", afterResponse: { res async throws in
                #expect(res.status == .ok)
                let csp = try #require(res.headers.first(name: "Content-Security-Policy"))
                let nonce = try #require(csp.split(separator: "'").first { $0.hasPrefix("nonce-") }).dropFirst("nonce-".count)
                #expect(res.body.string.contains(#"<script nonce="\#(nonce)">"#))
                #expect(res.body.string.contains(#"<style nonce="\#(nonce)">"#))
                #expect(!csp.contains("unsafe-inline"))
            })
            // Everything else keeps the strict default.
            try await app.test(.GET, "v1/test/status", afterResponse: { res async in
                #expect(res.headers.first(name: "Content-Security-Policy") == "default-src 'none'")
            })
        }
    }

    // MARK: Personas

    private func persona(_ app: Application, _ session: Session, _ name: String) async throws -> TestModeController.PersonaResponse {
        var out: TestModeController.PersonaResponse?
        try await post(app, "v1/test/persona", #"{"name":"\#(session.name)","persona":"\#(name)"}"#) { res in
            #expect(res.status == .ok, "\(res.body.string)")
            out = try res.content.decode(TestModeController.PersonaResponse.self)
        }
        return try #require(out)
    }

    @Test func athleteHasWeeksOfHistoryAndReseedingReplacesIt() async throws {
        try await withApp { app in
            let me = try await login(app)
            let first = try await persona(app, me, "athlete")
            #expect(first.pro)
            #expect(first.receipts == 8)
            #expect(first.streakDays == 56)
            let events = try await XPEvent.query(on: app.db).filter(\.$user.$id == me.userID).all()
            #expect(events.count == first.xpEvents)
            let oldest = try #require(events.compactMap(\.createdAt).min())
            #expect(Date().timeIntervalSince(oldest) > 7 * 7 * 86400)  // backdated, not "now"
            #expect(first.xpTotal == events.reduce(0) { $0 + $1.multipliedXP })

            let again = try await persona(app, me, "athlete")
            #expect(again.xpEvents == first.xpEvents)
            #expect(try await XPEvent.query(on: app.db).filter(\.$user.$id == me.userID).count() == first.xpEvents)
            #expect(try await Receipt.query(on: app.db).filter(\.$userID == me.userID).count() == 8)
        }
    }

    @Test func lapsedProStoppedThreeWeeksAgoAndLostPro() async throws {
        try await withApp { app in
            let me = try await login(app)
            let seeded = try await persona(app, me, "lapsed-pro")
            #expect(!seeded.pro)
            #expect(seeded.streakDays == 0)
            let newest = try #require(try await XPEvent.query(on: app.db).filter(\.$user.$id == me.userID).all().compactMap(\.createdAt).max())
            #expect(Date().timeIntervalSince(newest) > 20 * 86400)
            #expect(try await weeklyReport(app, me) == .paymentRequired)
        }
    }

    @Test func unknownPersona() async throws {
        try await withApp { app in
            let me = try await login(app)
            try await post(app, "v1/test/persona", #"{"name":"\#(me.name)","persona":"wizard"}"#) { res in
                #expect(res.status == .badRequest)
            }
        }
    }

    // MARK: AI recordings

    @Test func replayServesTheNewestRecordingThenFallsBackToFake() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tempo-rec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let recordings = AIRecordings(directory: dir)
        try recordings.save(feature: "weekly_plan", body: #"{"old":true}"#, at: Date(timeIntervalSince1970: 1_000))
        try recordings.save(feature: "weekly_plan", body: #"{"new":true}"#, at: Date(timeIntervalSince1970: 2_000))
        #expect(recordings.latest(feature: "weekly_plan") == #"{"new":true}"#)
        #expect(recordings.latest(feature: "nothing") == nil)
        #expect(recordings.counts() == ["weekly_plan": 2])

        try await withApp { app in
            let state = try #require(app.testMode)
            state.recordings = AIRecordings(directory: dir)
            state.aiMode = .replay
            let body = #"{"model":"claude-haiku","messages":[{"role":"user","content":"hello"}]}"#
            let feature = TestFixtures.claudeFeature(forRequestBody: body).name
            try state.recordings.save(feature: feature, body: #"{"recorded":"\#(feature)"}"#)
            var request = ClientRequest(method: .POST, url: "https://api.anthropic.com/v1/messages")
            request.body = ByteBuffer(string: body)
            let replayed = try await app.client.send(request).get()
            #expect(replayed.body.map { String(buffer: $0) } == #"{"recorded":"\#(feature)"}"#)

            state.recordings = AIRecordings(directory: dir.appendingPathComponent("empty"))
            let fallback = try await app.client.send(request).get()
            #expect(fallback.status == .ok)
            #expect(fallback.body.map { String(buffer: $0) }?.contains(#""type":"message""#) == true)
        }
    }

    // MARK: Shared lists

    @Test func sharedListsShowTheShopperLink() async throws {
        try await withApp { app in
            let me = try await login(app)
            try await app.test(.PUT, "v1/grocery/shared", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: me.access)
                req.headers.contentType = .json
                req.body = ByteBuffer(string: #"{"title":"Week","items":[{"id":"1","name":"Rice","quantity":1,"unit":"kg","category":"grains","checked":false,"updated_at":"2026-10-01T10:00:00Z"}]}"#)
            }, afterResponse: { res async in #expect(res.status == .ok) })
            try await app.test(.GET, "v1/test/shared?name=\(me.name)", afterResponse: { res async throws in
                let lists = try res.content.decode([TestModeController.SharedListInfo].self)
                #expect(lists.count == 1)
                #expect(lists.first?.items == 1)
                #expect(lists.first?.url.contains("/g/") == true)
            })
        }
    }
}
