import Fluent
import Vapor

// MARK: - Arena (test mode)

//
// POST /v1/test/arena {name, friends?, requests?} → who was added
// GET  /v1/test/invite?name=                       → that user's live invite link
//
// Real people are needed to try the leaderboard and challenges. The second
// simulator is one; this adds the rest: made-up friends with a week of XP and a
// level, plus a few waiting friend requests, so a single simulator can see a
// full board. Re-running replaces the earlier made-up people. The made-up
// people are ordinary test-mode users, so they never exist outside a local test
// server (this file is only reachable through /v1/test, which a deployed server
// never mounts).

extension TestModeController {
    func bootArena(routes: RoutesBuilder) {
        routes.post("arena", use: seedArena)
        routes.get("invite", use: inviteLink)
    }

    struct ArenaSeedRequest: Content {
        let name: String
        /// Friends to add (default 4, max 8).
        var friends: Int?
        /// Friend requests waiting for an answer (default 1, max 4).
        var requests: Int?
    }

    struct ArenaSeedResponse: Content {
        let friends: [String]
        let requests: [String]
    }

    private static let madeUp: [(name: String, level: Int, week: [Int])] = [
        ("Mia", 7, [220, 180, 260, 0, 240, 300, 120]),
        ("Jonas", 4, [90, 0, 140, 110, 0, 160, 80]),
        ("Sofia", 9, [300, 280, 310, 260, 290, 0, 0]),
        ("Luca", 2, [40, 0, 0, 60, 0, 0, 0]),
        ("Giulia", 5, [150, 130, 0, 170, 160, 0, 90]),
        ("Marco", 3, [0, 80, 70, 0, 90, 0, 0]),
        ("Elena", 6, [200, 0, 190, 210, 0, 180, 0]),
        ("Paolo", 1, [0, 0, 0, 0, 0, 0, 0]),
    ]

    private static let madeUpRequesters = ["Noah", "Chiara", "Davide", "Anna"]

    func seedArena(_ req: Request) async throws -> ArenaSeedResponse {
        _ = try Self.state(req)
        let body = try req.content.decode(ArenaSeedRequest.self)
        guard let me = try await User.query(on: req.db)
            .filter(\.$appleUserID == Self.appleUserID(for: body.name)).first()
        else {
            throw Abort(.notFound, reason: "No test user '\(body.name)' — sign in first (sim.sh qa --local --as \(body.name)).")
        }
        let myID = try me.requireID()
        let prefix = "test-arena:\(body.name):"

        // Replace the earlier made-up people (and everything that hung off them).
        let old = try await User.query(on: req.db).filter(\.$appleUserID ~~ (Self.madeUp.map { prefix + $0.name } + Self.madeUpRequesters.map { prefix + $0 })).all()
        for user in old {
            let id = try user.requireID()
            try await Friendship.query(on: req.db)
                .group(.or) { $0.filter(\.$userAID == id); $0.filter(\.$userBID == id) }
                .delete()
            try await FriendRequest.query(on: req.db)
                .group(.or) { $0.filter(\.$fromUserID == id); $0.filter(\.$toUserID == id) }
                .delete()
            try await ChallengeMember.query(on: req.db).filter(\.$userID == id).delete()
            try await ArenaDailyStat.query(on: req.db).filter(\.$userID == id).delete()
            try await FriendInvite.query(on: req.db).filter(\.$userID == id).delete()
            try await user.delete(on: req.db)
        }

        // This week's days, Monday first, relative to the (movable) server clock.
        let week = ArenaService.week(containing: req.now, requestedStart: nil)
        let today = ArenaService.dayString(req.now)

        var friends: [String] = []
        for person in Self.madeUp.prefix(min(max(body.friends ?? 4, 0), 8)) {
            let user = Self.fakeUser(prefix + person.name, name: person.name, level: person.level)
            try await user.save(on: req.db)
            let id = try user.requireID()
            for (offset, xp) in person.week.enumerated() where xp > 0 {
                guard let day = ArenaService.addDays(offset, to: week.start), day <= today else { continue }
                try await ArenaDailyStat(userID: id, day: day, xp: xp, workouts: xp > 150 ? 1 : 0, studyMinutes: xp > 100 ? 25 : 0)
                    .save(on: req.db)
            }
            try await ArenaService.befriend(myID, id, on: req.db)
            friends.append(person.name)
        }

        var requests: [String] = []
        for name in Self.madeUpRequesters.prefix(min(max(body.requests ?? 1, 0), 4)) {
            let user = Self.fakeUser(prefix + name, name: name, level: 3)
            try await user.save(on: req.db)
            try await FriendRequest(fromUserID: user.requireID(), toUserID: myID).save(on: req.db)
            requests.append(name)
        }
        return ArenaSeedResponse(friends: friends, requests: requests)
    }

    private static func fakeUser(_ appleID: String, name: String, level: Int) -> User {
        let user = User(appleUserID: appleID, username: "fake_\(UUID().uuidString.prefix(10).lowercased())", displayName: name)
        user.level = level
        user.tosAcceptedAt = Date()
        return user
    }

    struct InviteInfo: Content {
        let token: String
        let url: String
        let deepLink: String
    }

    func inviteLink(_ req: Request) async throws -> InviteInfo {
        _ = try Self.state(req)
        guard let id = try await Self.userFilter(req), id != "__none__" else {
            throw Abort(.notFound, reason: "No such test user.")
        }
        guard let invite = try await FriendInvite.query(on: req.db)
            .filter(\.$userID == id)
            .filter(\.$revokedAt == nil)
            .first()
        else {
            throw Abort(.notFound, reason: "No live invite link yet — tap Invite in the app first.")
        }
        let base = GroceryShareController.publicBaseURL(req: req)
        return InviteInfo(token: invite.token, url: "\(base)/i/\(invite.token)", deepLink: "tempo://invite/\(invite.token)")
    }
}
