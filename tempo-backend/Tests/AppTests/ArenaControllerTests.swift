@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - Arena: friends, invite links, leaderboard, challenges

//
// Real Postgres + Redis harness (same pattern as GroceryShareControllerTests).
// Covers what Nicola asked for in "Real friends and leaderboard": invite by
// link, real friends, a real weekly ranking, real challenges, and the privacy
// rule that friends see a display name, a level and XP and nothing else.

@Suite("Arena", .serialized)
struct ArenaControllerTests {
    // MARK: Harness

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

    private struct Person {
        let user: User
        let token: String
        var id: String {
            user.id ?? ""
        }
    }

    private func makePerson(_ app: Application, name: String, level: Int = 1) async throws -> Person {
        let suffix = UUID().uuidString.prefix(12)
        let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: name)
        user.tosAcceptedAt = Date()
        user.level = level
        try await user.save(on: app.db)
        let req = Request(application: app, on: app.eventLoopGroup.next())
        let token = try await JWTService.issueAccessToken(userID: user.requireID(), deviceID: "test-device", on: req)
        return Person(user: user, token: token)
    }

    private struct Reply {
        let status: HTTPStatus
        let body: Data
        var text: String {
            String(decoding: body, as: UTF8.self)
        }

        func json() throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        }

        func object() throws -> [String: Any] {
            try #require(json()["data"] as? [String: Any])
        }

        func array() throws -> [[String: Any]] {
            try #require(json()["data"] as? [[String: Any]])
        }
    }

    @discardableResult
    private func call(
        _ app: Application,
        _ method: HTTPMethod,
        _ path: String,
        as person: Person? = nil,
        json: [String: Any]? = nil
    ) async throws -> Reply {
        var reply: Reply?
        try await app.test(method, path, beforeRequest: { req in
            if let person {
                req.headers.bearerAuthorization = .init(token: person.token)
            }
            if let json {
                req.headers.contentType = .json
                req.body = try ByteBuffer(data: JSONSerialization.data(withJSONObject: json))
            }
        }, afterResponse: { res async throws in
            reply = Reply(status: res.status, body: Data(res.body.readableBytesView))
        })
        return try #require(reply)
    }

    private func today() -> String {
        ArenaService.dayString(Date())
    }

    private func daysFromToday(_ n: Int) -> String {
        ArenaService.addDays(n, to: today())!
    }

    private func befriend(_ a: Person, _ b: Person, _ app: Application) async throws {
        try await ArenaService.befriend(a.id, b.id, on: app.db)
    }

    /// Pushes per-day totals the way the app does.
    private func push(
        _ app: Application,
        _ person: Person,
        level: Int = 1,
        days: [(day: String, xp: Int, workouts: Int, study: Int)]
    ) async throws {
        let reply = try await call(app, .PUT, "v1/arena/stats", as: person, json: [
            "level": level, "xp_total": days.reduce(0) { $0 + $1.xp }, "streak_days": 1,
            "days": days.map { ["day": $0.day, "xp": $0.xp, "workouts": $0.workouts, "study_minutes": $0.study] },
        ])
        #expect(reply.status == .ok)
    }

    // MARK: Pure rules

    @Test func weekRunsMondayToSunday() throws {
        // Wed 2026-11-25
        let wednesday = try #require(ArenaService.parseDay("2026-11-25"))
        let week = ArenaService.week(containing: wednesday, requestedStart: nil)
        #expect(week.start == "2026-11-23")
        #expect(week.end == "2026-11-29")
        // Sunday still belongs to the week that started the Monday before.
        let sunday = try ArenaService.week(containing: #require(ArenaService.parseDay("2026-11-29")), requestedStart: nil)
        #expect(sunday.start == "2026-11-23")
        // The very next day starts a new week.
        let monday = try ArenaService.week(containing: #require(ArenaService.parseDay("2026-11-30")), requestedStart: nil)
        #expect(monday.start == "2026-11-30")
    }

    @Test func requestedWeekIsHonouredOnlyWhenNearAndValid() throws {
        let now = try #require(ArenaService.parseDay("2026-11-25"))
        #expect(ArenaService.week(containing: now, requestedStart: "2026-11-30").start == "2026-11-30")
        #expect(ArenaService.week(containing: now, requestedStart: "2020-01-01").start == "2026-11-23")
        #expect(ArenaService.week(containing: now, requestedStart: "nonsense").start == "2026-11-23")
    }

    @Test func dayParsingRejectsImpossibleDates() {
        #expect(ArenaService.parseDay("2026-02-31") == nil)
        #expect(ArenaService.parseDay("2026-2-3") == nil)
        #expect(ArenaService.parseDay("") == nil)
        #expect(ArenaService.addDays(1, to: "2026-12-31") == "2027-01-01")
    }

    @Test func tiesShareARank() {
        #expect(ArenaService.ranks(for: [300, 300, 120, 120, 0]) == [1, 1, 3, 3, 5])
        #expect(ArenaService.ranks(for: []) == [])
    }

    @Test func inviteTokensAreLongLowercaseAndDifferent() {
        let a = FriendInvite.makeToken()
        let b = FriendInvite.makeToken()
        #expect(a.count == 16)
        #expect(a != b)
        #expect(a.allSatisfy { $0.isNumber || ($0.isLetter && $0.isLowercase) })
    }

    // MARK: Invite link

    @Test func inviteLinkIsStableUntilRevoked() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let first = try await call(app, .POST, "v1/friends/invite", as: alice).object()
            let again = try await call(app, .POST, "v1/friends/invite", as: alice).object()
            let token = try #require(first["token"] as? String)
            #expect(again["token"] as? String == token)
            #expect((first["url"] as? String)?.hasSuffix("/i/\(token)") == true)
            #expect(first["display_name"] as? String == "Alice")

            try await call(app, .POST, "v1/friends/invite/revoke", as: alice)
            let fresh = try await call(app, .POST, "v1/friends/invite", as: alice).object()
            #expect(fresh["token"] as? String != token)

            // The old link is dead for everyone.
            let bob = try await makePerson(app, name: "Bob")
            let old = try await call(app, .POST, "v1/friends/invites/\(token)/accept", as: bob)
            #expect(old.status == .notFound)
        }
    }

    @Test func openingALinkMakesBothFriendsAtOnce() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice", level: 4)
            let bob = try await makePerson(app, name: "Bob")
            let token = try #require(try await call(app, .POST, "v1/friends/invite", as: alice).object()["token"] as? String)

            let preview = try await call(app, .GET, "v1/friends/invites/\(token)", as: bob).object()
            #expect(preview["display_name"] as? String == "Alice")
            #expect(preview["level"] as? Int == 4)
            #expect(preview["is_own"] as? Bool == false)
            #expect(preview["already_friends"] as? Bool == false)

            let accepted = try await call(app, .POST, "v1/friends/invites/\(token)/accept", as: bob)
            #expect(accepted.status == .ok)
            #expect(try accepted.object()["display_name"] as? String == "Alice")

            // Both sides see the other, and accepting twice changes nothing.
            #expect(try await call(app, .GET, "v1/friends", as: alice).array().map { $0["display_name"] as? String } == ["Bob"])
            #expect(try await call(app, .GET, "v1/friends", as: bob).array().map { $0["display_name"] as? String } == ["Alice"])
            #expect(try await call(app, .POST, "v1/friends/invites/\(token)/accept", as: bob).status == .ok)
            #expect(try await call(app, .GET, "v1/friends", as: bob).array().count == 1)
            let after = try await call(app, .GET, "v1/friends/invites/\(token)", as: bob).object()
            #expect(after["already_friends"] as? Bool == true)
        }
    }

    @Test func ownLinkAndUnknownLinkAreRefused() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let token = try #require(try await call(app, .POST, "v1/friends/invite", as: alice).object()["token"] as? String)
            #expect(try await call(app, .POST, "v1/friends/invites/\(token)/accept", as: alice).status == .badRequest)
            #expect(try await call(app, .GET, "v1/friends/invites/\(token)", as: alice).object()["is_own"] as? Bool == true)
            #expect(try await call(app, .POST, "v1/friends/invites/nosuchtoken/accept", as: alice).status == .notFound)
            #expect(try await call(app, .POST, "v1/friends/invite").status == .unauthorized)
        }
    }

    @Test func acceptingALinkClosesAPendingRequestBetweenTheTwo() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await call(app, .POST, "v1/friends/requests", as: bob, json: ["user_id": alice.id])
            let token = try #require(try await call(app, .POST, "v1/friends/invite", as: alice).object()["token"] as? String)
            try await call(app, .POST, "v1/friends/invites/\(token)/accept", as: bob)
            #expect(try await call(app, .GET, "v1/friends/requests", as: alice).array().isEmpty)
        }
    }

    // MARK: Public invite page

    @Test func publicPageShowsInviterAndOpensTheApp() async throws {
        try await withApp { app in
            let evil = try await makePerson(app, name: "<script>alert(1)</script> Al")
            let token = try #require(try await call(app, .POST, "v1/friends/invite", as: evil).object()["token"] as? String)
            let page = try await call(app, .GET, "i/\(token)")
            #expect(page.status == .ok)
            #expect(page.text.contains("tempo://invite/\(token)"))
            // The name is escaped, never raw markup.
            #expect(!page.text.contains("<script>alert"))
            #expect(page.text.contains("&lt;script&gt;"))
            // Nothing but the display name about the inviter.
            #expect(!page.text.contains(evil.user.username))
            #expect(!page.text.contains(evil.user.appleUserID))
        }
    }

    @Test func publicPageCarriesAStrictPolicyAndNoScript() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let token = try #require(try await call(app, .POST, "v1/friends/invite", as: alice).object()["token"] as? String)
            try await app.test(.GET, "i/\(token)", afterResponse: { res async throws in
                let csp = res.headers.first(name: "Content-Security-Policy") ?? ""
                #expect(csp.contains("default-src 'none'"))
                #expect(!csp.contains("script-src"))
                #expect(!csp.contains("unsafe-inline"))
                let html = String(buffer: res.body)
                #expect(!html.contains("<script"))
            })
        }
    }

    @Test func unknownOrRevokedLinkLooksTheSame() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let token = try #require(try await call(app, .POST, "v1/friends/invite", as: alice).object()["token"] as? String)
            try await call(app, .POST, "v1/friends/invite/revoke", as: alice)
            let revoked = try await call(app, .GET, "i/\(token)")
            let unknown = try await call(app, .GET, "i/zzzzzzzzzzzzzzzz")
            #expect(revoked.status == .gone)
            #expect(unknown.status == .gone)
            #expect(!revoked.text.contains("Alice"))
            #expect(!revoked.text.contains("tempo://"))
        }
    }

    // MARK: Friend requests

    @Test func requestAcceptFlowAndWhatEachSideSees() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice", level: 3)
            let bob = try await makePerson(app, name: "Bob", level: 2)

            let sent = try await call(app, .POST, "v1/friends/requests", as: alice, json: ["user_id": bob.id])
            #expect(sent.status == .created)
            #expect(try sent.object()["direction"] as? String == "outgoing")

            let bobSees = try await call(app, .GET, "v1/friends/requests", as: bob).array()
            #expect(bobSees.count == 1)
            #expect(bobSees[0]["direction"] as? String == "incoming")
            #expect(bobSees[0]["display_name"] as? String == "Alice")
            #expect(bobSees[0]["level"] as? Int == 3)
            let aliceSees = try await call(app, .GET, "v1/friends/requests", as: alice).array()
            #expect(aliceSees.first?["direction"] as? String == "outgoing")

            let requestID = try #require(bobSees[0]["id"] as? String)
            // The sender cannot accept their own request.
            #expect(try await call(app, .POST, "v1/friends/requests/\(requestID)/accept", as: alice).status == .forbidden)
            #expect(try await call(app, .POST, "v1/friends/requests/\(requestID)/accept", as: bob).status == .ok)
            #expect(try await call(app, .GET, "v1/friends/requests", as: bob).array().isEmpty)
            #expect(try await call(app, .GET, "v1/friends", as: alice).array().count == 1)
            // Answered requests can't be answered again.
            #expect(try await call(app, .POST, "v1/friends/requests/\(requestID)/decline", as: bob).status == .conflict)
        }
    }

    @Test func declinedRequestCanBeSentAgainWithoutAServerError() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await call(app, .POST, "v1/friends/requests", as: alice, json: ["user_id": bob.id])
            let id = try #require(try await call(app, .GET, "v1/friends/requests", as: bob).array().first?["id"] as? String)
            try await call(app, .POST, "v1/friends/requests/\(id)/decline", as: bob)
            #expect(try await call(app, .GET, "v1/friends/requests", as: bob).array().isEmpty)

            let again = try await call(app, .POST, "v1/friends/requests", as: alice, json: ["user_id": bob.id])
            #expect(again.status == .created)
            #expect(try await call(app, .GET, "v1/friends/requests", as: bob).array().count == 1)
            // A second one while pending is a conflict, not a duplicate.
            #expect(try await call(app, .POST, "v1/friends/requests", as: alice, json: ["user_id": bob.id]).status == .conflict)
        }
    }

    @Test func askingSomeoneWhoAlreadyAskedYouMakesYouFriends() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await call(app, .POST, "v1/friends/requests", as: alice, json: ["user_id": bob.id])
            let back = try await call(app, .POST, "v1/friends/requests", as: bob, json: ["user_id": alice.id])
            #expect(back.status == .created)
            #expect(try await call(app, .GET, "v1/friends", as: bob).array().count == 1)
            #expect(try await call(app, .GET, "v1/friends/requests", as: bob).array().isEmpty)
            #expect(try await call(app, .GET, "v1/friends/requests", as: alice).array().isEmpty)
        }
    }

    @Test func requestEdgeCases() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            #expect(try await call(app, .POST, "v1/friends/requests", as: alice, json: ["user_id": alice.id]).status == .badRequest)
            #expect(try await call(app, .POST, "v1/friends/requests", as: alice, json: ["user_id": "nobody"]).status == .notFound)
            try await befriend(alice, bob, app)
            #expect(try await call(app, .POST, "v1/friends/requests", as: alice, json: ["user_id": bob.id]).status == .conflict)
        }
    }

    // MARK: Friends list, privacy, removal

    @Test func friendRowsCarryOnlyNameLevelAndXP() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob", level: 5)
            try await befriend(alice, bob, app)
            try await push(app, bob, level: 5, days: [(today(), 120, 1, 0)])

            let reply = try await call(app, .GET, "v1/friends", as: alice)
            let row = try #require(reply.array().first)
            #expect(Set(row.keys) == ["friendship_id", "user_id", "display_name", "level", "weekly_xp", "friends_since"])
            #expect(row["display_name"] as? String == "Bob")
            #expect(row["level"] as? Int == 5)
            #expect(row["weekly_xp"] as? Int == 120)
            #expect(!reply.text.contains(bob.user.username))
            #expect(!reply.text.contains(bob.user.appleUserID))
        }
    }

    @Test func removingAFriendEndsItForBothAndStrangersCannot() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            let eve = try await makePerson(app, name: "Eve")
            try await befriend(alice, bob, app)
            let friendshipID = try #require(try await call(app, .GET, "v1/friends", as: alice).array().first?["friendship_id"] as? String)

            #expect(try await call(app, .DELETE, "v1/friends/\(friendshipID)", as: eve).status == .forbidden)
            #expect(try await call(app, .DELETE, "v1/friends/\(friendshipID)", as: bob).status == .ok)
            #expect(try await call(app, .GET, "v1/friends", as: alice).array().isEmpty)
            #expect(try await call(app, .GET, "v1/friends", as: bob).array().isEmpty)
            // They can become friends again later.
            try await befriend(alice, bob, app)
            #expect(try await call(app, .GET, "v1/friends", as: alice).array().count == 1)
        }
    }

    // MARK: Stats push

    @Test func pushingADayTwiceReplacesItInsteadOfAddingUp() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            try await push(app, alice, days: [(today(), 80, 1, 10)])
            try await push(app, alice, days: [(today(), 90, 1, 10)])
            let rows = try await ArenaDailyStat.query(on: app.db).filter(\.$userID == alice.id).all()
            #expect(rows.count == 1)
            #expect(rows.first?.xp == 90)
        }
    }

    @Test func pushedValuesAreBoundedAndOldOrFutureDaysAreDropped() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            try await push(app, alice, level: 9999, days: [
                (today(), 999_999, 500, 99999),
                (daysFromToday(-200), 50, 0, 0), // too old
                (daysFromToday(30), 50, 0, 0), // far in the future
            ])
            let rows = try await ArenaDailyStat.query(on: app.db).filter(\.$userID == alice.id).all()
            #expect(rows.count == 1)
            #expect(rows[0].xp == ArenaStatsController.maxXPPerDay)
            #expect(rows[0].workouts == ArenaStatsController.maxWorkoutsPerDay)
            #expect(rows[0].studyMinutes == ArenaStatsController.maxStudyMinutesPerDay)
            let user = try #require(try await User.find(alice.id, on: app.db))
            #expect(user.level == 100)
        }
    }

    @Test func badDayIsRejectedAndLoginIsRequired() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bad = try await call(app, .PUT, "v1/arena/stats", as: alice, json: [
                "level": 1, "xp_total": 0, "streak_days": 0,
                "days": [["day": "yesterday", "xp": 1, "workouts": 0, "study_minutes": 0]],
            ])
            #expect(bad.status == .badRequest)
            #expect(try await call(app, .PUT, "v1/arena/stats", json: ["level": 1]).status == .unauthorized)
        }
    }

    @Test func pushingStatsUpdatesTheNameAndLevelFriendsSee() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await befriend(alice, bob, app)
            let reply = try await call(app, .PUT, "v1/arena/stats", as: bob, json: [
                "display_name": "  Bobby  ", "level": 7, "xp_total": 900, "streak_days": 4, "days": [],
            ])
            #expect(reply.status == .ok)
            let row = try #require(try await call(app, .GET, "v1/friends", as: alice).array().first)
            #expect(row["display_name"] as? String == "Bobby")
            #expect(row["level"] as? Int == 7)
        }
    }

    // MARK: Leaderboard

    @Test func leaderboardRanksFriendsByThisWeeksRealXP() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            let cara = try await makePerson(app, name: "Cara")
            let stranger = try await makePerson(app, name: "Stranger")
            try await befriend(alice, bob, app)
            try await befriend(alice, cara, app)
            try await push(app, alice, days: [(today(), 200, 1, 0)])
            try await push(app, bob, days: [(today(), 500, 1, 0)])
            try await push(app, cara, days: [(today(), 200, 0, 0)])
            try await push(app, stranger, days: [(today(), 9000, 1, 0)])

            let board = try await call(app, .GET, "v1/leaderboards/friends", as: alice).object()
            let rows = try #require(board["rankings"] as? [[String: Any]])
            // Bob first; Alice and Cara tie on 200, share rank 2, and the strangers' 9000 is nowhere.
            #expect(rows.map { ($0["user"] as? [String: Any])?["display_name"] as? String } == ["Bob", "Alice", "Cara"])
            #expect(rows.map { $0["rank"] as? Int } == [1, 2, 2])
            #expect(rows.map { $0["xp"] as? Int } == [500, 200, 200])
            #expect(rows.map { $0["is_me"] as? Bool } == [false, true, false])
            #expect(board["my_rank"] as? Int == 2)
            #expect(board["my_xp"] as? Int == 200)
            #expect(board["period"] as? String == "weekly")
        }
    }

    @Test func leaderboardEntriesCarryNoUsernameOrEmail() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await befriend(alice, bob, app)
            let reply = try await call(app, .GET, "v1/leaderboards/friends", as: alice)
            let rows = try #require(try reply.object()["rankings"] as? [[String: Any]])
            for row in rows {
                #expect(Set(row.keys) == ["rank", "user", "xp", "is_me"])
                #expect(Set((row["user"] as? [String: Any] ?? [:]).keys) == ["id", "display_name", "level"])
            }
            #expect(!reply.text.contains(bob.user.username))
            #expect(!reply.text.contains(bob.user.appleUserID))
        }
    }

    @Test func aFriendWithNoXPYetStillAppearsWithZero() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await befriend(alice, bob, app)
            let board = try await call(app, .GET, "v1/leaderboards/friends", as: alice).object()
            let rows = try #require(board["rankings"] as? [[String: Any]])
            #expect(rows.count == 2)
            #expect(rows.allSatisfy { $0["xp"] as? Int == 0 && $0["rank"] as? Int == 1 })
        }
    }

    @Test func lastWeeksXPDoesNotCountThisWeek() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            // Exactly seven days ago is always in the previous ISO week.
            try await push(app, alice, days: [(daysFromToday(-7), 700, 1, 0), (today(), 30, 0, 0)])
            let board = try await call(app, .GET, "v1/leaderboards/friends", as: alice).object()
            #expect(board["my_xp"] as? Int == 30)
        }
    }

    @Test func removedFriendLeavesTheBoard() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await befriend(alice, bob, app)
            let id = try #require(try await call(app, .GET, "v1/friends", as: alice).array().first?["friendship_id"] as? String)
            try await call(app, .DELETE, "v1/friends/\(id)", as: alice)
            let rows = try #require(try await call(app, .GET, "v1/leaderboards/friends", as: bob).object()["rankings"] as? [[String: Any]])
            #expect(rows.count == 1)
        }
    }

    @Test func theGlobalBoardIsGone() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            for period in ["weekly", "monthly", "alltime"] {
                #expect(try await call(app, .GET, "v1/leaderboards/\(period)", as: alice).status == .notFound)
            }
        }
    }

    // MARK: Challenges

    private func createChallenge(
        _ app: Application,
        by creator: Person,
        title: String = "Seven day XP race",
        metric: String = "xp_total",
        days: Int = 7,
        startsOn: String? = nil,
        invite: [Person] = []
    ) async throws -> Reply {
        var body: [String: Any] = [
            "title": title, "metric": metric, "duration_days": days,
            "invite_user_ids": invite.map(\.id),
        ]
        if let startsOn {
            body["starts_on"] = startsOn
        }
        return try await call(app, .POST, "v1/challenges", as: creator, json: body)
    }

    @Test func onlyFriendsCanBeInvitedToAChallenge() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            let stranger = try await makePerson(app, name: "Stranger")
            try await befriend(alice, bob, app)
            #expect(try await createChallenge(app, by: alice, invite: [bob, stranger]).status == .forbidden)
            #expect(try await createChallenge(app, by: alice, invite: [bob]).status == .created)
        }
    }

    @Test func challengeScoresAreTheRealDailyTotalsInsideItsDays() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await befriend(alice, bob, app)
            let created = try await createChallenge(app, by: alice, days: 3, startsOn: daysFromToday(-1), invite: [bob])
            let id = try #require(try created.object()["id"] as? String)
            #expect(try await call(app, .POST, "v1/challenges/\(id)/join", as: bob).status == .ok)

            // Yesterday and today count; two days ago is before the challenge began.
            try await push(app, alice, days: [(daysFromToday(-2), 400, 0, 0), (daysFromToday(-1), 100, 0, 0), (today(), 50, 0, 0)])
            try await push(app, bob, days: [(today(), 300, 0, 0)])

            let detail = try await call(app, .GET, "v1/challenges/\(id)", as: alice).object()
            let people = try #require(detail["participants"] as? [[String: Any]])
            #expect(people.map { $0["display_name"] as? String } == ["Bob", "Alice"])
            #expect(people.map { $0["score"] as? Int } == [300, 150])
            #expect(people.map { $0["rank"] as? Int } == [1, 2])
            #expect(detail["my_score"] as? Int == 150)
            #expect(detail["my_rank"] as? Int == 2)
            #expect(detail["status"] as? String == "active")
            #expect(detail["start_day"] as? String == daysFromToday(-1))
            #expect(detail["end_day"] as? String == daysFromToday(1))
        }
    }

    @Test func eachMetricReadsItsOwnColumn() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            try await push(app, alice, days: [(today(), 80, 2, 45)])
            for (metric, expected) in [("xp_total", 80), ("workout_count", 2), ("study_minutes", 45)] {
                let created = try await createChallenge(app, by: alice, title: "Race \(metric)", metric: metric, days: 1)
                #expect(try created.object()["my_score"] as? Int == expected)
            }
        }
    }

    @Test func challengeStatusFollowsTheCalendar() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let upcoming = try await createChallenge(app, by: alice, title: "Next week", startsOn: daysFromToday(3))
            #expect(try upcoming.object()["status"] as? String == "upcoming")
            let active = try await createChallenge(app, by: alice, title: "Running now")
            #expect(try active.object()["status"] as? String == "active")
            // One day, started yesterday: already over.
            let ended = try await createChallenge(app, by: alice, title: "Yesterday only", days: 1, startsOn: daysFromToday(-1))
            #expect(try ended.object()["status"] as? String == "completed")

            let activeOnly = try await call(app, .GET, "v1/challenges?status=active", as: alice).array()
            #expect(activeOnly.map { $0["title"] as? String } == ["Running now"])
            #expect(try await call(app, .GET, "v1/challenges", as: alice).array().count == 3)
        }
    }

    @Test func challengeInputIsValidated() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            #expect(try await createChallenge(app, by: alice, title: "ab").status == .badRequest)
            #expect(try await createChallenge(app, by: alice, metric: "steps").status == .badRequest)
            #expect(try await createChallenge(app, by: alice, days: 0).status == .badRequest)
            #expect(try await createChallenge(app, by: alice, days: 91).status == .badRequest)
            #expect(try await createChallenge(app, by: alice, startsOn: daysFromToday(-5)).status == .badRequest)
            #expect(try await createChallenge(app, by: alice, startsOn: "2026-02-31").status == .badRequest)
        }
    }

    @Test func invitedFriendSeesItJoinsOrDeclines() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            let cara = try await makePerson(app, name: "Cara")
            try await befriend(alice, bob, app)
            try await befriend(alice, cara, app)
            let created = try await createChallenge(app, by: alice, invite: [bob, cara])
            let id = try #require(try created.object()["id"] as? String)

            let mine = try await call(app, .GET, "v1/challenges", as: bob).array()
            #expect(mine.first?["my_status"] as? String == "invited")
            #expect(mine.first?["my_rank"] == nil || mine.first?["my_rank"] is NSNull)

            // Declining an invite takes it off Cara's list and leaves Alice's standings alone.
            #expect(try await call(app, .POST, "v1/challenges/\(id)/leave", as: cara).status == .ok)
            #expect(try await call(app, .GET, "v1/challenges", as: cara).array().isEmpty)
            #expect(try await call(app, .POST, "v1/challenges/\(id)/join", as: bob).status == .ok)
            #expect(try await call(app, .POST, "v1/challenges/\(id)/join", as: bob).status == .conflict)

            let detail = try await call(app, .GET, "v1/challenges/\(id)", as: alice).object()
            let people = try #require(detail["participants"] as? [[String: Any]])
            #expect(Set(people.compactMap { $0["display_name"] as? String }) == ["Alice", "Bob"])
            #expect(detail["member_count"] as? Int == 2)
        }
    }

    @Test func outsidersCannotSeeOrJoinAChallenge() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            let stranger = try await makePerson(app, name: "Stranger")
            try await befriend(alice, bob, app)
            let id = try #require(try await createChallenge(app, by: alice).object()["id"] as? String)
            #expect(try await call(app, .GET, "v1/challenges/\(id)", as: stranger).status == .forbidden)
            #expect(try await call(app, .POST, "v1/challenges/\(id)/join", as: stranger).status == .forbidden)
            // A friend of the creator can walk in without an invite.
            #expect(try await call(app, .POST, "v1/challenges/\(id)/join", as: bob).status == .ok)
        }
    }

    @Test func aFinishedChallengeCannotBeJoined() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            let bob = try await makePerson(app, name: "Bob")
            try await befriend(alice, bob, app)
            let id = try #require(try await createChallenge(app, by: alice, days: 1, startsOn: daysFromToday(-1)).object()["id"] as? String)
            #expect(try await call(app, .POST, "v1/challenges/\(id)/join", as: bob).status == .conflict)
        }
    }

    @Test func creatorCanHaveFiveRunningChallengesNotSix() async throws {
        try await withApp { app in
            let alice = try await makePerson(app, name: "Alice")
            for n in 1 ... 5 {
                #expect(try await createChallenge(app, by: alice, title: "Race number \(n)").status == .created)
            }
            #expect(try await createChallenge(app, by: alice, title: "Race number 6").status == .tooManyRequests)
        }
    }

    // MARK: Test-mode seeding (local test server only)

    @Test func modeSeedsMadeUpFriendsAndRequestsAndReplacesThemOnRerun() async throws {
        let app = try await Application.make(.testing)
        TestMode.force(true, on: app)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()

            let name = "arena-seed-\(UUID().uuidString.prefix(6).lowercased())"
            var token = ""
            try await app.test(.POST, "v1/test/login", beforeRequest: { req in
                req.headers.contentType = .json
                req.headers.replaceOrAdd(name: "X-Device-Id", value: "arena-test-device")
                req.body = ByteBuffer(string: #"{"name":"\#(name)","fresh":true,"pro":true}"#)
            }, afterResponse: { res async throws in
                token = try res.content.decode(TestModeController.LoginResponse.self).accessToken
            })
            let me = Person(user: User(appleUserID: "", username: "", displayName: ""), token: token)

            func seed(friends: Int, requests: Int) async throws -> Reply {
                try await call(app, .POST, "v1/test/arena", json: ["name": name, "friends": friends, "requests": requests])
            }
            let first = try await seed(friends: 4, requests: 2)
            #expect(first.status == .ok)
            #expect(try first.json()["friends"] as? [String] == ["Mia", "Jonas", "Sofia", "Luca"])
            #expect(try await call(app, .GET, "v1/friends", as: me).array().count == 4)
            let requests = try await call(app, .GET, "v1/friends/requests", as: me).array()
            #expect(requests.count == 2)
            #expect(requests.allSatisfy { $0["direction"] as? String == "incoming" })

            // Running it again replaces them instead of piling up.
            _ = try await seed(friends: 2, requests: 0)
            #expect(try await call(app, .GET, "v1/friends", as: me).array().count == 2)
            #expect(try await call(app, .GET, "v1/friends/requests", as: me).array().isEmpty)

            // The invite link of a user who has made one can be read back.
            #expect(try await call(app, .GET, "v1/test/invite?name=\(name)").status == .notFound)
            try await call(app, .POST, "v1/friends/invite", as: me)
            let link = try await call(app, .GET, "v1/test/invite?name=\(name)").json()
            #expect((link["deep_link"] as? String)?.hasPrefix("tempo://invite/") == true)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
